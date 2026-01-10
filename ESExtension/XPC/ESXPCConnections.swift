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
                Logfile.es.log("Got active XPC connection on attempt #\(idx + 1, privacy: .public)")
                completion(conn)
                return
            }

            if idx >= min(maxRetries - 1, delays.count - 1) {
                Logfile.es.log("No XPC connection after quick retries (attempts=\(idx + 1, privacy: .public), giving up)")
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
        xpcLock.perform {
            self.activeConnections.append(conn)
            Logfile.es.log("Stored incoming XPC connection — total=\(self.activeConnections.count, privacy: .public)")
        }
    }

    // Remove a connection when it goes away.
    func removeIncomingConnection(_ conn: NSXPCConnection) {
        xpcLock.perform {
            self.activeConnections.removeAll { $0 === conn }
            self.authenticatedConnections.remove(ObjectIdentifier(conn))
            Logfile.es.log("Removed XPC connection — total=\(self.activeConnections.count, privacy: .public)")
        }
    }

    // Pick the first available active connection.
    func pickAppConnection() -> NSXPCConnection? {
        return xpcLock.sync {
            return self.activeConnections.first
        }
    }
}
