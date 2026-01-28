//
//  ESXPCClient.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation
import os

final class ESXPCClient {
    static let shared = ESXPCClient()
    private var connection: NSXPCConnection?
    private let serviceName = "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc"
    private let maxRetries = 10
    private var retryCount = 0
    private var isConnecting = false  // Prevent parallel connection attempts

    // pending queue if updateBlockedApps called before connection ready
    private var lastKnownBlockedApps: [[String: String]] = []

    private init() {
        // tiny delay to avoid race but keep it short
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            [weak self] in
            self?.connect()
        }
    }

    private let xpcQueue = DispatchQueue(
        label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc.qos",
        qos: .userInitiated
    )

    func connect() {
        xpcQueue.async { [weak self] in
            guard let self = self else { return }

            // Prevent multiple concurrent connection attempts
            guard self.connection == nil, !self.isConnecting else {
                return
            }
            self.isConnecting = true

            Logfile.core.log("[ESXPCClient] Connecting to MachService")

            let conn = NSXPCConnection(machServiceName: self.serviceName)
            conn.remoteObjectInterface = NSXPCInterface(with: ESAppProtocol.self)
            conn.exportedInterface = NSXPCInterface(with: ESXPCProtocol.self)
            conn.exportedObject = XPCServer.shared

            conn.invalidationHandler = { [weak self] in
                self?.scheduleReconnect(immediate: true)
            }

            conn.interruptionHandler = { [weak self] in
                self?.scheduleReconnect(immediate: false)
            }

            conn.resume()

            // Perform Authentication Handshake
            self.performAuth(conn: conn) { [weak self] success in
                guard let self = self else { return }
                if success {
                    Logfile.core.log("[ESXPCClient] Authentication successful. Connection ready.")
                    self.connection = conn
                    self.retryCount = 0
                    self.isConnecting = false  // Clear flag on success

                    if !self.lastKnownBlockedApps.isEmpty {
                        let copy = self.lastKnownBlockedApps
                        self.xpcQueue.async {
                            self.updateBlockedApps(copy)
                        }
                    }

                    if let langs = UserDefaults.standard.array(forKey: "AppleLanguages")
                        as? [String],
                        let primary = langs.first {
                        self.updateLanguage(primary)
                    }
                } else {
                    Logfile.core.error(
                        "[ESXPCClient] Authentication failed. Invalidating connection.")
                    self.isConnecting = false  // Clear flag on failure
                    conn.invalidate()
                    // Reconnect logic will trigger via invalidationHandler
                }
            }
        }
    }

    private func performAuth(conn: NSXPCConnection, completion: @escaping (Bool) -> Void) {
        let appTag = KeychainHelper.Keys.appPublic

        // 1. Ensure Client Keys
        if !KeychainHelper.shared.hasKey(tag: appTag) {
            Logfile.core.log("[ESXPCClient] Client keys missing, generating...")
            do {
                try KeychainHelper.shared.generateKeys(tag: appTag)
            } catch {
                Logfile.core.error("[ESXPCClient] Key gen failed: \(error.localizedDescription)")
                completion(false)
                return
            }
        }

        // 2. Prepare Auth Data
        let clientNonce = Data.random(count: 32)
        guard let clientSig = KeychainHelper.shared.sign(data: clientNonce, tag: appTag) else {
            Logfile.core.error("[ESXPCClient] Failed to sign client nonce")
            completion(false)
            return
        }

        // 2b. Export Public Key
        guard let pubKeyData = KeychainHelper.shared.exportPublicKey(tag: appTag) else {
            Logfile.core.error("[ESXPCClient] Failed to export public key")
            completion(false)
            return
        }

        // 3. Send to Server
        guard
            let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                Logfile.core.error("[ESXPCClient] Auth XPC error: \(error.localizedDescription)")
                completion(false)
            }) as? ESAppProtocol
        else {
            completion(false)
            return
        }

        proxy.authenticate(
            clientNonce: clientNonce, clientSig: clientSig, clientPublicKey: pubKeyData
        ) { serverNonce, serverSig, serverPubKey, success in
            guard success, let serverNonce = serverNonce, let serverSig = serverSig,
                let serverPubKey = serverPubKey
            else {
                Logfile.core.error("[ESXPCClient] Server rejected auth or invalid response")
                completion(false)
                return
            }

            // 4. Verify Server (Curve25519)
            let combined = clientNonce + serverNonce

            if KeychainHelper.shared.verify(
                signature: serverSig, originalData: combined, publicKeyData: serverPubKey) {
                completion(true)
            } else {
                Logfile.core.error("[ESXPCClient] Server signature verification failed!")
                completion(false)
            }
        }
    }

    private func scheduleReconnect(immediate: Bool) {
        xpcQueue.async { [weak self] in
            guard let self = self else { return }

            // Clean up existing connection
            self.connection?.invalidate()
            self.connection = nil
            self.isConnecting = false  // Allow new connection attempt

            guard self.retryCount < self.maxRetries else {
                Logfile.core.error("[ESXPCClient] Max retries reached (\(self.maxRetries))")
                return
            }
            self.retryCount += 1

            let delay: Double
            if immediate {
                delay = 0.05  // try quickly
            } else {
                delay = min(0.5 * Double(self.retryCount), 1.0)  // gentle backoff but small cap
            }

            Logfile.core.log(
                "[ESXPCClient] Retrying in \(delay, format: .fixed(precision: 2))s (attempt \(self.retryCount))"
            )
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                [weak self] in
                self?.connect()
            }
        }
    }

    // Public API
    // Accepts Swift array of dicts, converts to NSArray for XPC
    func updateBlockedApps(_ apps: [[String: String]]) {
        guard let conn = connection else {
            Logfile.core.log("[ESXPCClient] Connection not ready, queueing updateBlockedApps")
            lastKnownBlockedApps = apps
            return
        }

        guard
            let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                Logfile.core.pError(
                    "updateBlockedApps failed: \(String(describing: error))")
            }) as? ESAppProtocol
        else {
            Logfile.core.error("[ESXPCClient] No valid proxy to send update")
            return
        }

        let ns = apps.map { NSDictionary(dictionary: $0) } as NSArray
        proxy.updateBlockedApps(ns)
        Logfile.core.pLog("updateBlockedApps sent (\(apps.count) items)")
    }

    // App requests extension to allow SHA once (with reply ack)
    func allowSHAOnce(
        _ sha: String,
        retry: Int = 0,
        completion: @escaping (Bool) -> Void
    ) {
        guard retry <= 10 else {
            Logfile.core.error("allowSHAOnce retry limit reached for SHA \(sha.prefix(8))")
            completion(false)
            return
        }

        guard let conn = connection else {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
                self.allowSHAOnce(sha, retry: retry + 1, completion: completion)
            }
            return
        }

        guard
            let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                Logfile.core.pError(
                    "allowSHAOnce failed: \(String(describing: error))")
                completion(false)
            }) as? ESAppProtocol
        else {
            completion(false)
            return
        }

        proxy.allowSHAOnce(sha) { success in
            completion(success)
        }
    }

    func updateLanguage(_ langCode: String) {
        guard let conn = connection else {
            Logfile.core.log("[ESXPCClient] Connection not ready, skipping language update")
            return
        }

        guard
            let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                Logfile.core.pError(
                    "updateLanguage failed: \(String(describing: error))")
            }) as? ESAppProtocol
        else {
            Logfile.core.error("[ESXPCClient] No valid proxy to send language update")
            return
        }

        proxy.updateLanguage(to: langCode)
        Logfile.core.pLog("updateLanguage sent: \(langCode)")
    }

    // App requests extension to allow config access once (with reply ack)
    func allowConfigAccess(_ processID: Int32, completion: @escaping (Bool) -> Void) {
        guard let conn = connection else {
            // quick retry once after 50ms
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
                self.allowConfigAccess(processID, completion: completion)
            }
            return
        }

        guard
            let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                Logfile.core.pError(
                    "allowConfigAccess failed: \(String(describing: error))")
                completion(false)
            }) as? ESAppProtocol
        else {
            Logfile.core.error("[ESXPCClient] No valid proxy to send allowConfigAccess")
            completion(false)
            return
        }

        proxy.allowConfigAccess(processID) { success in
            Logfile.core.log(
                "allowConfigAccess reply: \(success ? "success" : "fail") for PID=\(processID)")
            completion(success)
        }
    }
}
