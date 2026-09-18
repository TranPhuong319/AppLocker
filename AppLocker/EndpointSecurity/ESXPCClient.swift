//
//  ESXPCClient.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation
import os

final class ESXPCClient: @unchecked Sendable {
    static let shared = ESXPCClient()
    private var connection: NSXPCConnection?
    private var pendingConnection: NSXPCConnection?
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
        onError: @escaping @Sendable () -> Void = {}
    ) -> ESAppProtocol? {
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            Logfile.appXPC.error(
                "[ESXPCClient] \(actionName, privacy: .public) failed: \(String(describing: error))"
            )
            onError()
        }) as? ESAppProtocol else {
            Logfile.appXPC.error("[ESXPCClient] No valid proxy for \(actionName, privacy: .public)")
            onError()
            return nil
        }
        return proxy
    }

    func connect() {
        xpcQueue.async { [weak self] in
            guard let self = self, self.connection == nil, !self.isConnecting else { return }
            self.shouldReconnect = true
            self.isConnecting = true

            Logfile.appXPC.debug("[ESXPCClient] Connecting to MachService")
            let conn = self.createConnection()
            self.setupConnectionHandlers(conn: conn)
            conn.resume()
            self.pendingConnection = conn

            guard let proxy = self.proxy(conn: conn, actionName: "Connect", onError: { [weak self] in
                self?.handleAuthResult(success: false)
            }) else {
                self.handleAuthResult(success: false)
                return
            }

            proxy.allowConfigAccess(getpid()) { [weak self] success in
                self?.handleAuthResult(success: success)
            }
        }
    }

    private func createConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: ESAppProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: ESXPCProtocol.self)
        conn.exportedObject = XPCServer.shared
        return conn
    }

    private func updateExtensionInstalledState(_ installed: Bool) {
        Task { @MainActor in
            ExtensionInstaller.shared.updateInstalledState(installed)
        }
    }

    private func setupConnectionHandlers(conn: NSXPCConnection) {
        conn.invalidationHandler = { [weak self] in
            self?.updateExtensionInstalledState(false)
            self?.scheduleReconnect(immediate: true)
        }

        conn.interruptionHandler = { [weak self] in
            self?.updateExtensionInstalledState(false)
            self?.scheduleReconnect(immediate: false)
        }
    }

    private func handleAuthResult(success: Bool) {
        xpcQueue.async { [weak self] in
            guard let self else { return }
            self.isConnecting = false
            guard let pendingConn = self.pendingConnection else { return }
            self.pendingConnection = nil

            if success {
                Logfile.appXPC.info("[ESXPCClient] Authentication successful. Connection ready.")
                self.connection = pendingConn
                self.retryCount = 0
                self.updateExtensionInstalledState(true)
                if let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
                   let primary = langs.first {
                    self.updateLanguage(primary)
                }
            } else {
                Logfile.appXPC.error("[ESXPCClient] Authentication failed. Invalidating connection.")
                self.updateExtensionInstalledState(false)
                pendingConn.invalidate()
            }
        }
    }

    func disconnect() {
        xpcQueue.async { [weak self] in
            guard let self else { return }
            self.shouldReconnect = false
            self.retryCount = 0
            self.isConnecting = false

            if let pending = self.pendingConnection {
                pending.invalidationHandler = nil
                pending.interruptionHandler = nil
                pending.invalidate()
                self.pendingConnection = nil
            }

            if let oldConn = self.connection {
                oldConn.invalidationHandler = nil
                oldConn.interruptionHandler = nil
                oldConn.invalidate()
            }
            self.connection = nil

            self.updateExtensionInstalledState(false)
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

            self.updateExtensionInstalledState(false)

            guard self.retryCount < self.maxRetries else {
                Logfile.appXPC.error("[ESXPCClient] Max retries reached (\(self.maxRetries, privacy: .public))")
                self.updateExtensionInstalledState(false)
                return
            }
            self.retryCount += 1

            let delay: Double
            if immediate {
                delay = 0.05  // try quickly
            } else {
                delay = min(0.5 * Double(self.retryCount), 1.0)  // gentle backoff but small cap
            }

            Logfile.appXPC.debug(
                """
                [ESXPCClient] Retrying in \(delay, format: .fixed(precision: 2))s \
                (attempt \(self.retryCount, privacy: .public))
                """
            )
            self.xpcQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.shouldReconnect else { return }
                self.connect()
            }
        }
    }
}

// MARK: - XPC Request Actions
extension ESXPCClient {
    func updateLanguage(_ langCode: String) {
        xpcQueue.async { [weak self] in
            guard let self = self, let conn = self.connection else {
                Logfile.appXPC.debug("[ESXPCClient] Connection not ready, skipping language update")
                return
            }

            guard let proxy = self.proxy(conn: conn, actionName: "updateLanguage") else { return }
            proxy.updateLanguage(to: langCode)
            Logfile.appXPC.debug("[ESXPCClient] updateLanguage sent: \(langCode, privacy: .public)")
        }
    }

    // App requests extension to allow config access once (with reply ack)
    func allowConfigAccess(_ processID: Int32, retry: Int = 0, completion: @escaping @Sendable (Bool) -> Void) {
        xpcQueue.async { [weak self] in
            guard let self else {
                completion(false)
                return
            }

            guard retry <= 10 else {
                Logfile.appXPC.error("[ESXPCClient] allowConfigAccess: Max retries reached, giving up.")
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
                let replyStatus = success ? "success" : "fail"
                Logfile.appXPC.debug(
                    """
                    [ESXPCClient] allowConfigAccess reply: \(replyStatus, privacy: .public) \
                    for PID=\(processID, privacy: .public)
                    """
                )
                completion(success)
            }
        }
    }

    func authorizeShutdown(_ authorized: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        xpcQueue.async { [weak self] in
            guard let self = self, let conn = self.connection else {
                completion(false)
                return
            }

            guard let proxy = self.proxy(conn: conn, actionName: "authorizeShutdown", onError: { completion(false) })
            else { return }

            proxy.authorizeShutdown(authorized) { success in
                Logfile.appXPC.debug("[ESXPCClient] authorizeShutdown reply: \(success, privacy: .public)")
                completion(success)
            }
        }
    }

    func processPendingApps(
        approvedPIDs: [Int32],
        rejectedPIDs: [Int32],
        retry: Int = 0,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        xpcQueue.async { [weak self] in
            guard let self else {
                completion(false)
                return
            }

            guard retry <= 5 else {
                Logfile.appXPC.error("[ESXPCClient] processPendingApps retry limit reached (connection unavailable)")
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
                Logfile.appXPC.debug(
                    """
                    [ESXPCClient] processPendingApps reply: \(success, privacy: .public) \
                    (Approved: \(approvedPIDs, privacy: .public), Rejected: \(rejectedPIDs, privacy: .public))
                    """
                )
                completion(success)
            }
        }
    }

    func updateIncomingCallRingingState(_ isRinging: Bool) {
        xpcQueue.async { [weak self] in
            guard let self, let conn = self.connection else {
                Logfile.appXPC.debug("[ESXPCClient] Connection not ready, skipping call state update")
                return
            }

            guard let proxy = self.proxy(conn: conn, actionName: "updateIncomingCallRingingState") else { return }
            proxy.updateIncomingCallRingingState(isRinging)
            Logfile.appXPC.debug(
                "[ESXPCClient] updateIncomingCallRingingState sent: \(isRinging, privacy: .public)"
            )
        }
    }
}
