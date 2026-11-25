//
//  ESXPCClient.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation
import os

struct ESXPCClientConfiguration: Sendable {
    var maxRetries: Int = 10
    var connectionFactory: @Sendable () -> NSXPCConnection
    var isExtensionInstalled: @Sendable () -> Bool
    var onConnectionEstablished: @Sendable () -> Void
    var onMaxRetriesReached: @Sendable () -> Void
    var reconnectDelay: @Sendable (_ attempt: Int, _ immediate: Bool) -> TimeInterval

    static let live = ESXPCClientConfiguration(
        maxRetries: 10,
        connectionFactory: {
            let serviceName = "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc"
            let conn = NSXPCConnection(machServiceName: serviceName)
            conn.remoteObjectInterface = NSXPCInterface(with: ESAppProtocol.self)
            conn.exportedInterface = NSXPCInterface(with: ESXPCProtocol.self)
            conn.exportedObject = XPCServer.shared
            return conn
        },
        isExtensionInstalled: { ExtensionInstaller.isExtensionInstalled },
        onConnectionEstablished: {
            Task { @MainActor in ExtensionInstaller.shared.updateInstalledState(true) }
        },
        onMaxRetriesReached: {
            Task { @MainActor in ExtensionInstaller.shared.refreshStatus(reconnectIfEnabled: false) }
        },
        reconnectDelay: { attempt, immediate in
            immediate ? 0.05 : min(0.5 * Double(attempt), 1.0)
        }
    )
}

final class ESXPCClient: @unchecked Sendable {
    static let shared = ESXPCClient()
    var connection: NSXPCConnection?
    private var pendingConnection: NSXPCConnection?
    let configuration: ESXPCClientConfiguration
    private var retryCount = 0
    private var isConnecting = false  // Prevent parallel connection attempts
    private var pendingReconnectWorkItem: DispatchWorkItem?
    private let shouldReconnectLock = OSAllocatedUnfairLock(initialState: true)
    var shouldReconnect: Bool {
        get { shouldReconnectLock.withLock { $0 } }
        set { shouldReconnectLock.withLock { $0 = newValue } }
    }

    let xpcQueue = DispatchQueue(
        label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc.qos",
        qos: .userInitiated
    )

    init(configuration: ESXPCClientConfiguration = .live, connectOnInit: Bool = true) {
        self.configuration = configuration
        if connectOnInit && configuration.isExtensionInstalled() {
            xpcQueue.async { [weak self] in self?.attemptConnect() }
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
            guard let self else { return }
            self.pendingReconnectWorkItem?.cancel()
            self.pendingReconnectWorkItem = nil
            self.shouldReconnect = true
            self.retryCount = 0
            self.attemptConnect()
        }
    }

    private func attemptConnect() {
        guard connection == nil, !isConnecting, shouldReconnect else { return }
        guard configuration.isExtensionInstalled() else {
            Logfile.appXPC.debug("[ESXPCClient] Extension is not installed, skipping connect")
            return
        }
        isConnecting = true

        Logfile.appXPC.debug("[ESXPCClient] Connecting to MachService")
        let conn = configuration.connectionFactory()
        setupConnectionHandlers(conn: conn)
        conn.resume()
        pendingConnection = conn

        let targetID = ObjectIdentifier(conn)
        guard let proxy = proxy(conn: conn, actionName: "Connect", onError: { [weak self] in
            self?.handleAuthResult(success: false, isTransportError: true, for: targetID)
        }) else {
            handleAuthResult(success: false, isTransportError: true, for: targetID)
            return
        }

        proxy.allowConfigAccess(getpid()) { [weak self] success in
            self?.handleAuthResult(success: success, isTransportError: false, for: targetID)
        }
    }

    private func isActiveOrPending(_ targetID: ObjectIdentifier) -> Bool {
        connection.map(ObjectIdentifier.init) == targetID
            || pendingConnection.map(ObjectIdentifier.init) == targetID
    }

    private func setupConnectionHandlers(conn: NSXPCConnection) {
        let targetID = ObjectIdentifier(conn)
        conn.invalidationHandler = { [weak self] in
            self?.xpcQueue.async { [weak self] in
                guard let self, self.isActiveOrPending(targetID) else { return }
                let wasEstablished = self.connection.map(ObjectIdentifier.init) == targetID
                self.scheduleReconnectOnQueue(immediate: wasEstablished)
            }
        }

        conn.interruptionHandler = { [weak self] in
            self?.xpcQueue.async { [weak self] in
                guard let self, self.isActiveOrPending(targetID) else { return }
                self.scheduleReconnectOnQueue(immediate: false)
            }
        }
    }

    private func handleAuthResult(success: Bool, isTransportError: Bool, for targetID: ObjectIdentifier) {
        xpcQueue.async { [weak self] in
            guard let self,
                  let pendingConn = self.pendingConnection,
                  ObjectIdentifier(pendingConn) == targetID else { return }
            self.isConnecting = false
            self.pendingConnection = nil

            if success {
                Logfile.appXPC.info("[ESXPCClient] Authentication successful. Connection ready.")
                self.pendingReconnectWorkItem?.cancel()
                self.pendingReconnectWorkItem = nil
                self.connection = pendingConn
                self.retryCount = 0
                self.configuration.onConnectionEstablished()
                if let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
                   let primary = langs.first {
                    self.updateLanguage(primary)
                }
            } else {
                pendingConn.invalidationHandler = nil
                pendingConn.interruptionHandler = nil
                pendingConn.invalidate()
                if isTransportError {
                    Logfile.appXPC.warning("[ESXPCClient] Handshake transport error. Scheduling reconnect.")
                    self.scheduleReconnectOnQueue(immediate: false)
                } else {
                    Logfile.appXPC.error("[ESXPCClient] Authentication failed. Invalidating connection.")
                    self.shouldReconnect = false
                }
            }
        }
    }

    func disconnect() {
        xpcQueue.async { [weak self] in
            guard let self else { return }
            self.pendingReconnectWorkItem?.cancel()
            self.pendingReconnectWorkItem = nil
            self.shouldReconnect = false
            self.retryCount = 0
            self.isConnecting = false
            self.invalidateConnectionsOnQueue()
        }
    }

    private func invalidateConnectionsOnQueue() {
        dispatchPrecondition(condition: .onQueue(xpcQueue))
        for conn in [pendingConnection, connection].compactMap({ $0 }) {
            conn.invalidationHandler = nil
            conn.interruptionHandler = nil
            conn.invalidate()
        }
        pendingConnection = nil
        connection = nil
    }

    private func scheduleReconnectOnQueue(immediate: Bool) {
        dispatchPrecondition(condition: .onQueue(xpcQueue))
        pendingReconnectWorkItem?.cancel()
        pendingReconnectWorkItem = nil

        invalidateConnectionsOnQueue()
        isConnecting = false

        guard shouldReconnect, configuration.isExtensionInstalled() else { return }

        guard retryCount < configuration.maxRetries else {
            Logfile.appXPC.error(
                "[ESXPCClient] Max retries reached (\(self.configuration.maxRetries, privacy: .public))"
            )
            shouldReconnect = false
            configuration.onMaxRetriesReached()
            return
        }
        retryCount += 1

        let delay = configuration.reconnectDelay(retryCount, immediate)
        Logfile.appXPC.debug(
            """
            [ESXPCClient] Retrying in \(delay, format: .fixed(precision: 2))s \
            (attempt \(self.retryCount, privacy: .public))
            """
        )
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.shouldReconnect else { return }
            self.pendingReconnectWorkItem = nil
            self.attemptConnect()
        }
        pendingReconnectWorkItem = workItem
        xpcQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
