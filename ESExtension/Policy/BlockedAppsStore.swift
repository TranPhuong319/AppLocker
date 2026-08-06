//
//  BlockedAppsStore.swift
//  ESExtension
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import os

extension ESManager {
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
            xpcConnectionLock.perform {
                Logfile.endpointSecurity.warning(
                    "No XPC connection available. Queueing notification and forcing App wake-up for UID \(notification.uid)..."
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
            Logfile.endpointSecurity.error(
                "XPC notify (async) error: \(String(describing: error))")
        }) as? ESXPCProtocol {
            proxy.notifyBlockedExec(name: name, path: path, cdhash: cdhash, pid: rawPID)
            Logfile.endpointSecurity.log("Notified app (async) about blocked exec: \(path) (PID: \(rawPID))")
        } else {
            Logfile.endpointSecurity.error("Failed to notify app: Could not obtain valid XPC proxy for ESXPCProtocol")
        }
    }
}
