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
        var count = 0

        xpcConnectionLock.perform {
            self.activeConnections.append(conn)
            count = self.activeConnections.count
        }

        Logfile.endpointSecurity.log("Stored incoming XPC connection — total=\(count)")
    }

    // Flush pending notifications to a specific connection (called after Auth)
    func flushPendingNotifications(to conn: NSXPCConnection) {
        var pendingToFlush: [BlockedNotification] = []

        xpcConnectionLock.perform {
            // Lấy các thông báo đang chờ để gửi đi
            pendingToFlush = self.pendingNotifications
            self.pendingNotifications.removeAll()
        }

        if !pendingToFlush.isEmpty {
            Logfile.endpointSecurity.log("Auth complete. Flushing \(pendingToFlush.count) pending notifications...")
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
        var count = 0
        xpcConnectionLock.perform {
            self.activeConnections.removeAll { $0 === conn }
            self.authenticatedConnections.remove(ObjectIdentifier(conn))
            count = self.activeConnections.count
        }
        Logfile.endpointSecurity.log("Removed XPC connection — total=\(count)")
    }

    // Pick the first available active connection.
    func pickAppConnection() -> NSXPCConnection? {
        return xpcConnectionLock.sync {
            return self.activeConnections.first
        }
    }
}
