//
//  ESXPCClient.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import CryptoKit
import Foundation
import os

final class ESXPCClient {
    static let shared = ESXPCClient()
    private var connection: NSXPCConnection?
    private let serviceName = "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc"
    private let maxRetries = 10
    private var retryCount = 0
    private var isConnecting = false  // Prevent parallel connection attempts
    private var shouldReconnect = true

    private let xpcQueue = DispatchQueue(
        label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc.qos",
        qos: .userInitiated
    )

    private init() {
        xpcQueue.async { [weak self] in
            self?.connect()
        }
    }

    private func proxy(
        conn: NSXPCConnection,
        actionName: String,
        onError: @escaping () -> Void = {}
    ) -> ESAppProtocol? {
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            Logfile.core.error("\(actionName) failed: \(String(describing: error))")
            onError()
        }) as? ESAppProtocol else {
            Logfile.core.error("[ESXPCClient] No valid proxy for \(actionName)")
            onError()
            return nil
        }
        return proxy
    }

    func connect() {
        xpcQueue.async { [weak self] in
            guard let self = self else { return }
            self.shouldReconnect = true

            // Prevent multiple concurrent connection attempts
            guard self.connection == nil, !self.isConnecting else {
                return
            }
            self.isConnecting = true

            Logfile.core.log("[ESXPCClient] Connecting to MachService")

            let server = XPCServer.shared
            let conn = NSXPCConnection(machServiceName: self.serviceName)
            conn.remoteObjectInterface = NSXPCInterface(with: ESAppProtocol.self)
            conn.exportedInterface = NSXPCInterface(with: ESXPCProtocol.self)
            conn.exportedObject = server

            conn.invalidationHandler = { [weak self] in
                DispatchQueue.main.async {
                    ExtensionInstaller.shared.updateInstalledState(false)
                }
                self?.scheduleReconnect(immediate: true)
            }

            conn.interruptionHandler = { [weak self] in
                DispatchQueue.main.async {
                    ExtensionInstaller.shared.updateInstalledState(false)
                }
                self?.scheduleReconnect(immediate: false)
            }

            conn.resume()

            // Perform Authentication Handshake
            self.performAuth(conn: conn) { [weak self] success in
                guard let self = self else { return }
                self.xpcQueue.async {
                    if success {
                        Logfile.core.log("[ESXPCClient] Authentication successful. Connection ready.")
                        self.connection = conn
                        self.retryCount = 0
                        self.isConnecting = false  // Clear flag on success

                        DispatchQueue.main.async {
                            ExtensionInstaller.shared.updateInstalledState(true)
                        }

                        if let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
                           let primary = langs.first {
                            self.updateLanguage(primary)
                        }
                    } else {
                        Logfile.core.error("[ESXPCClient] Authentication failed. Invalidating connection.")
                        self.isConnecting = false  // Clear flag on failure
                        DispatchQueue.main.async {
                            ExtensionInstaller.shared.updateInstalledState(false)
                        }
                        conn.invalidate()
                        // Reconnect logic will trigger via invalidationHandler
                    }
                }
            }
        }
    }

    func disconnect() {
        xpcQueue.async { [weak self] in
            guard let self = self else { return }
            self.shouldReconnect = false
            self.retryCount = 0
            self.isConnecting = false

            if let oldConn = self.connection {
                oldConn.invalidationHandler = nil
                oldConn.interruptionHandler = nil
                oldConn.invalidate()
            }
            self.connection = nil

            DispatchQueue.main.async {
                ExtensionInstaller.shared.updateInstalledState(false)
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
        let clientNonce = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
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
        guard let proxy = self.proxy(conn: conn, actionName: "Auth XPC", onError: { completion(false) }) else {
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

            // 4. Verify Server
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
            guard let self = self, self.shouldReconnect else { return }

            // Clean up existing connection safely without triggering recursive handler
            if let oldConn = self.connection {
                oldConn.invalidationHandler = nil
                oldConn.interruptionHandler = nil
                oldConn.invalidate()
            }
            self.connection = nil
            self.isConnecting = false  // Allow new connection attempt

            DispatchQueue.main.async {
                ExtensionInstaller.shared.updateInstalledState(false)
            }

            guard self.retryCount < self.maxRetries else {
                Logfile.core.error("[ESXPCClient] Max retries reached (\(self.maxRetries))")
                DispatchQueue.main.async {
                    ExtensionInstaller.shared.updateInstalledState(false)
                }
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
            self.xpcQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.shouldReconnect else { return }
                self.connect()
            }
        }
    }

    func updateLanguage(_ langCode: String) {
        xpcQueue.async { [weak self] in
            guard let self = self, let conn = self.connection else {
                Logfile.core.log("[ESXPCClient] Connection not ready, skipping language update")
                return
            }

            guard let proxy = self.proxy(conn: conn, actionName: "updateLanguage") else { return }
            proxy.updateLanguage(to: langCode)
            Logfile.core.log("updateLanguage sent: \(langCode)")
        }
    }

    // App requests extension to allow config access once (with reply ack)
    func allowConfigAccess(_ processID: Int32, retry: Int = 0, completion: @escaping (Bool) -> Void) {
        xpcQueue.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }

            guard retry <= 10 else {
                Logfile.core.error("[ESXPCClient] allowConfigAccess: Max retries reached, giving up.")
                completion(false)
                return
            }

            guard let conn = self.connection else {
                self.xpcQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.allowConfigAccess(processID, retry: retry + 1, completion: completion)
                }
                return
            }

            guard let proxy = self.proxy(conn: conn, actionName: "allowConfigAccess", onError: { completion(false) })
            else { return }

            proxy.allowConfigAccess(processID) { success in
                Logfile.core.log(
                    "allowConfigAccess reply: \(success ? "success" : "fail") for PID=\(processID)")
                completion(success)
            }
        }
    }

    func authorizeShutdown(_ authorized: Bool, completion: @escaping (Bool) -> Void) {
        xpcQueue.async { [weak self] in
            guard let self = self, let conn = self.connection else {
                completion(false)
                return
            }

            guard let proxy = self.proxy(conn: conn, actionName: "authorizeShutdown", onError: { completion(false) })
            else { return }

            proxy.authorizeShutdown(authorized) { success in
                Logfile.core.log("authorizeShutdown reply: \(success)")
                completion(success)
            }
        }
    }

    func processPendingApps(
        approvedPIDs: [Int32],
        rejectedPIDs: [Int32],
        retry: Int = 0,
        completion: @escaping (Bool) -> Void
    ) {
        xpcQueue.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }

            guard retry <= 5 else {
                Logfile.core.error("processPendingApps retry limit reached (connection unavailable)")
                completion(false)
                return
            }

            guard let conn = self.connection else {
                self.xpcQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.processPendingApps(
                        approvedPIDs: approvedPIDs,
                        rejectedPIDs: rejectedPIDs,
                        retry: retry + 1,
                        completion: completion
                    )
                }
                return
            }

            guard let proxy = self.proxy(conn: conn, actionName: "processPendingApps", onError: { completion(false) })
            else { return }

            proxy.processPendingApps(approvedPIDs: approvedPIDs, rejectedPIDs: rejectedPIDs) { success in
                Logfile.core.log(
                    "processPendingApps reply: \(success) (Approved: \(approvedPIDs), Rejected: \(rejectedPIDs))"
                )
                completion(success)
            }
        }
    }
}


