//
//  BlockedAppsStore.swift
//  ESExtension
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import os

extension ESManager {
    // Notify the app when an execution is blocked.
    func sendBlockedNotificationToApp(name: String, path: String, sha: String, uid: uid_t) {
        // Fix Recursive Lock Crash:
        // pickAppConnection() uses lock.sync, so we CANNOT call it inside lock.perform
        // Instead, we just call pickAppConnection() directly.
        if let conn = self.pickAppConnection() {
            self.performNotifyBlockRequest(conn: conn, name: name, path: path, sha: sha)
        } else {
            // Only lock when we need to modify pendingNotifications
            xpcConnectionLock.perform {
                // Double check connection inside lock to be sure?
                // No, just trust the first check to avoid complexity.
                // If connection appeared in between, we just queue it anyway, which is fine (handled by next flush).
                
                Logfile.endpointSecurity.warning("No XPC connection available. Queueing notification and forcing App wake-up for UID \(uid)...")
                let pending = BlockedNotification(name: name, path: path, sha: sha, uid: uid)
                self.pendingNotifications.append(pending)
            }
            // Execute wake-up OUTSIDE the lock to avoid any side effects
            AppLauncherUtils.forceEnableAndRestartAgent(for: uid)
        }
    }

    func performNotifyBlockRequest(conn: NSXPCConnection, name: String, path: String, sha: String) {
        if let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            Logfile.endpointSecurity.error(
                "XPC notify (async) error: \(String(describing: error))")
        }) as? ESXPCProtocol {
            proxy.notifyBlockedExec(name: name, path: path, sha: sha)
            Logfile.endpointSecurity.log("Notified app (async) about blocked exec: \(path)")
            return
        }

        if let syncProxy = conn.synchronousRemoteObjectProxyWithErrorHandler({ error in
            Logfile.endpointSecurity.error(
                "XPC notify (sync) error: \(String(describing: error))")
        }) as? ESXPCProtocol {
            syncProxy.notifyBlockedExec(name: name, path: path, sha: sha)
            Logfile.endpointSecurity.log(
                "Notified app (sync fallback) about blocked exec: \(path)")
            return
        }
        
        Logfile.endpointSecurity.error("Failed to notify app: Could not obtain valid XPC proxy for ESXPCProtocol")
    }
}
