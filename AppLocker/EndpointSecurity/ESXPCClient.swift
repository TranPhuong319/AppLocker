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
    var connection: NSXPCConnection?
    private var pendingConnection: NSXPCConnection?
    private let serviceName = "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc"
    private let maxRetries = 10
    private var retryCount = 0
    private var isConnecting = false  // Prevent parallel connection attempts
    var shouldReconnect = true

    let xpcQueue = DispatchQueue(
        label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc.qos",
        qos: .userInitiated
    )

    private init() {
        if ExtensionInstaller.isExtensionInstalled {
            xpcQueue.async { [weak self] in self?.connect() }
        }
    }

    func proxy(
        conn: NSXPCConnection,
        actionName: String,
        onError: @escaping @Sendable () -> Void = {}
    ) -> ESAppProtocol? {
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            Logfile.appXPC.error("[ESXPCClient] \(actionName, privacy: .public) failed: \(String(describing: error))")
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
            guard ExtensionInstaller.isExtensionInstalled else {
                Logfile.appXPC.debug("[ESXPCClient] Extension is not installed, skipping connect")
                return
            }
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
        Task { @MainActor in ExtensionInstaller.shared.updateInstalledState(installed) }
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
                self.shouldReconnect = false
                self.updateExtensionInstalledState(false)
                pendingConn.invalidationHandler = nil
                pendingConn.interruptionHandler = nil
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

            for conn in [self.pendingConnection, self.connection].compactMap({ $0 }) {
                conn.invalidationHandler = nil
                conn.interruptionHandler = nil
                conn.invalidate()
            }
            self.pendingConnection = nil
            self.connection = nil
            self.updateExtensionInstalledState(false)
        }
    }

    private func scheduleReconnect(immediate: Bool) {
        xpcQueue.async { [weak self] in
            guard let self = self, self.shouldReconnect, ExtensionInstaller.isExtensionInstalled else { return }

            if let oldConn = self.connection {
                oldConn.invalidationHandler = nil
                oldConn.interruptionHandler = nil
                oldConn.invalidate()
            }
            self.connection = nil
            self.isConnecting = false

            self.updateExtensionInstalledState(false)

            guard self.retryCount < self.maxRetries else {
                Logfile.appXPC.error("[ESXPCClient] Max retries reached (\(self.maxRetries, privacy: .public))")
                return
            }
            self.retryCount += 1

            let delay = immediate ? 0.05 : min(0.5 * Double(self.retryCount), 1.0)
            Logfile.appXPC.debug(
                """
                [ESXPCClient] Retrying in \(delay, format: .fixed(precision: 2))s \
                (attempt \(self.retryCount, privacy: .public))
                """
            )
            self.xpcQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.shouldReconnect, ExtensionInstaller.isExtensionInstalled else { return }
                self.connect()
            }
        }
    }
}
