//
//  ESXPCConnections.swift
//  ESExtension
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import os

extension ESManager {
    // Try to obtain an active app connection with short backoff retries.
    func withRetryPickAppConnection(
        maxRetries: Int = 6,
        delays: [TimeInterval] = [0.0, 0.01, 0.02, 0.05, 0.1, 0.25],
        completion: @escaping (NSXPCConnection?) -> Void
    ) {
        func attempt(_ idx: Int) {
            if let conn = self.pickAppConnection() {
                Logfile.endpointSecurity.log("Got active XPC connection on attempt #\(idx + 1)")
                completion(conn)
                return
            }
            
            if idx >= min(maxRetries - 1, delays.count - 1) {
                Logfile.endpointSecurity.log(
                    "No XPC connection after quick retries (attempts=\(idx + 1), giving up)"
                )
                completion(nil)
                return
            }
            
            let delay = delays[min(idx + 1, delays.count - 1)]
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                attempt(idx + 1)
            }
        }
        attempt(0)
    }
    
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
                    self?.performNotifyBlockRequest(conn: conn, name: item.name, path: item.path, sha: item.sha)
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
