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
                Logfile.es.log("No XPC connection available after retries — cannot notify app")
                return
            }

            if let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                Logfile.es.pError(
                    "XPC notify (async) error: \(String(describing: error))")
            }) as? ESXPCProtocol {
                proxy.notifyBlockedExec(name: name, path: path, sha: sha)
                Logfile.es.pLog("Notified app (async) about blocked exec: \(path)")
                return
            }

            if let syncProxy = conn.synchronousRemoteObjectProxyWithErrorHandler({ error in
                Logfile.es.pError(
                    "XPC notify (sync) error: \(String(describing: error))")
            }) as? ESXPCProtocol {
                syncProxy.notifyBlockedExec(name: name, path: path, sha: sha)
                Logfile.es.pLog(
                    "Notified app (sync fallback) about blocked exec: \(path)")
                return
            }
        }
    }

    // Replace blocked app data with new mapping from the host app.
    @objc func updateBlockedApps(_ apps: NSArray) {
        guard isCurrentConnectionAuthenticated() else {
            Logfile.es.error("Unauthorized call to updateBlockedApps")
            return
        }

        var newShas = Set<String>()
        var newPathToSha: [String: String] = [:]

        for item in apps {
            guard let dict = item as? [String: Any] ?? item as? NSDictionary as? [String: Any]
            else { continue }

            if let sha = dict["sha256"] as? String {
                newShas.insert(sha)
                if let path = dict["path"] as? String {
                    newPathToSha[path] = sha
                }
            }
        }

        stateLock.perform { [weak self] in
            guard let self = self else { return }
            self.blockedSHAs = newShas
            self.blockedPathToSHA.merge(newPathToSha) { (_, new) in new }
        }

        Logfile.es.log(
            "updateBlockedApps applied: \(newShas.count) SHAs, \(newPathToSha.count) paths"
        )
    }
}
