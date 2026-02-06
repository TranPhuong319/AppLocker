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
    func sendBlockedNotificationToApp(name: String, path: String, sha: String) {
        withRetryPickAppConnection { conn in
            guard let conn = conn else {
                Logfile.endpointSecurity.log("No XPC connection available after retries — cannot notify app")
                return
            }

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
        }
    }
}
