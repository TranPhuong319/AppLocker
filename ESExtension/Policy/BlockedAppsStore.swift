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
    func sendBlockedNotificationToApp(name: String, path: String, cdhash: String, uid: uid_t, targetPid: pid_t) {
        if let conn = self.pickAppConnection() {
            self.performNotifyBlockRequest(conn: conn, name: name, path: path, cdhash: cdhash, targetPid: targetPid)
        } else {
            xpcConnectionLock.perform {
                Logfile.endpointSecurity.warning(
                    "No XPC connection available. Queueing notification and forcing App wake-up for UID \(uid)..."
                )
                let pending = BlockedNotification(
                    name: name,
                    path: path,
                    cdhash: cdhash,
                    uid: uid,
                    targetPid: targetPid
                )
                self.pendingNotifications.append(pending)
            }
            AppLauncherUtils.forceEnableAndRestartAgent(for: uid)
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
            return
        }

        if let syncProxy = conn.synchronousRemoteObjectProxyWithErrorHandler({ error in
            Logfile.endpointSecurity.error(
                "XPC notify (sync) error: \(String(describing: error))")
        }) as? ESXPCProtocol {
            syncProxy.notifyBlockedExec(name: name, path: path, cdhash: cdhash, pid: rawPID)
            Logfile.endpointSecurity.log(
                "Notified app (sync fallback) about blocked exec: \(path) (PID: \(rawPID))")
            return
        }

        Logfile.endpointSecurity.error("Failed to notify app: Could not obtain valid XPC proxy for ESXPCProtocol")
    }
}
