//
//  ESXPCConnections.swift
//  ESExtension
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import os

extension ESManager {
    // Store an incoming connection (thread-safe).
    func storeIncomingConnection(_ conn: NSXPCConnection) {
        let boxed = XPCConn(connection: conn)
        let count = xpcConnectionLock.withLock { () -> Int in
            self.activeConnections.append(boxed)
            return self.activeConnections.count
        }

        Logfile.esXPC.debug("[ESConnections] Stored incoming XPC connection - total=\(count, privacy: .public)")
    }

    // Flush pending notifications to a specific connection (called after Auth)
    func flushPendingNotifications(to conn: NSXPCConnection) {
        let pendingToFlush = xpcConnectionLock.withLock { () -> [BlockedNotification] in
            let pending = self.pendingNotifications
            self.pendingNotifications.removeAll()
            return pending
        }

        if !pendingToFlush.isEmpty {
            Logfile.esXPC.debug(
                """
                [ESConnections] Auth complete. \
                Flushing \(pendingToFlush.count, privacy: .public) pending notifications...
                """
            )
            for item in pendingToFlush {
                self.performNotifyBlockRequest(
                    conn: conn,
                    name: item.name,
                    path: item.path,
                    cdhash: item.cdhash,
                    targetPid: item.targetPid
                )
            }
        }
    }

    // Remove a connection when it goes away.
    func removeIncomingConnection(_ conn: NSXPCConnection) {
        let boxed = XPCConn(connection: conn)
        let connID = ObjectIdentifier(conn)
        let count = xpcConnectionLock.withLock { () -> Int in
            self.activeConnections.removeAll { $0 == boxed }
            self.authenticatedConnections.remove(connID)
            return self.activeConnections.count
        }
        Logfile.esXPC.debug("[ESConnections] Removed XPC connection - total=\(count, privacy: .public)")
    }

    // Pick the first available active connection.
    func pickAppConnection() -> NSXPCConnection? {
        let boxed = xpcConnectionLock.withLock {
            self.activeConnections.first
        }
        return boxed?.connection
    }

    // MARK: - Outgoing Block Notifications

    func sendBlockedNotificationToApp(notification: BlockedNotification) {
        if let conn = self.pickAppConnection() {
            self.performNotifyBlockRequest(
                conn: conn,
                name: notification.name,
                path: notification.path,
                cdhash: notification.cdhash,
                targetPid: notification.targetPid
            )
        } else {
            xpcConnectionLock.withLock {
                Logfile.endpointSecurity.warning(
                    """
                    [ESConnections] No XPC connection available. Queueing notification and \
                    forcing App wake-up for UID \(notification.uid, privacy: .public)...
                    """
                )
                self.pendingNotifications.append(notification)
            }
            AppLauncherUtils.forceEnableAndRestartAgent(for: notification.uid)
        }
    }

    func performNotifyBlockRequest(
        conn: NSXPCConnection,
        name: String,
        path: String,
        cdhash: String,
        targetPid: pid_t
    ) {
        let rawPID = Int32(targetPid)
        if let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            Logfile.esXPC.error(
                "[ESConnections] XPC notify error: \(String(describing: error))")
        }) as? ESXPCProtocol {
            proxy.notifyBlockedExec(name: name, path: path, cdhash: cdhash, pid: rawPID)
            Logfile.esXPC.debug(
                """
                [ESConnections] Notified app about blocked exec: \(path, privacy: .public) \
                (PID: \(rawPID, privacy: .public))
                """
            )
        } else {
            Logfile.esXPC.error(
                "[ESConnections] Failed to notify app: Could not obtain valid XPC proxy for ESXPCProtocol"
            )
        }
    }
}
