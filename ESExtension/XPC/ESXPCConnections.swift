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
            DispatchQueue.global(qos: .utility).async { [weak self] in
                for item in pendingToFlush {
                    self?.performNotifyBlockRequest(
                        conn: conn,
                        name: item.name,
                        path: item.path,
                        cdhash: item.cdhash,
                        targetPid: item.targetPid
                    )
                }
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
}
