//
//  ESEventAuthExec.swift
//  ESExtension
//
//  Created by Doe Phương on 2/1/26.
//

import Foundation
import EndpointSecurity
import os

extension ESManager {
    static func handleAuthExec(
        client: OpaquePointer,
        message: UnsafePointer<es_message_t>) {
        let msg = message.pointee

        guard let path = safePath(fromFilePointer: msg.event.exec.target.pointee.executable) else {
            Logfile.es.log("Missing exec path in AUTH_EXEC. Denying by default.")
            es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
            return
        }

        guard let mgr = ESManager.sharedInstanceForCallbacks else {
            Logfile.es.log("No ESManager instance. Denying exec.")
            es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
            return
        }

        let parentPid = msg.process.pointee.ppid
        var signingID = "Unsigned/Unknown"
        if let signingToken = msg.event.exec.target.pointee.signing_id.data {
            signingID = String(cString: signingToken)
        }

        func sendNotifications(sha: String, decision: ExecDecision) {
            if decision == .deny {
                DispatchQueue.global(qos: .userInteractive).async {
                    TTYNotifier.notify(parentPid: parentPid, blockedPath: path, sha: sha, identifier: signingID)
                }
                DispatchQueue.global(qos: .utility).async {
                    let name = mgr.computeAppName(forExecPath: path)
                    mgr.sendBlockedNotificationToApp(name: name, path: path, sha: sha)
                }
            }
        }

        // Fast path — single lock read of all state.
        let decisionResult: ExecDecision? = mgr.stateLock.sync {
            if let mappedSHA = mgr.blockedPathToSHA[path] {
                if let expiry = mgr.tempAllowedSHAs[mappedSHA], expiry > Date() {
                    return .allow
                }
                if mgr.blockedSHAs.contains(mappedSHA) {
                    return .deny
                }
            }
            if let cached = mgr.decisionCache[path] {
                return cached
            }
            return nil
        }

        if let decision = decisionResult {
            let authResult = (decision == .allow) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
            es_respond_auth_result(client, message, authResult, false)

            if decision == .deny {
                Logfile.es.log("Denied by FastPath (Cache/Map): \(path, privacy: .public)")
                let shaForNotify = mgr.stateLock.sync { mgr.blockedPathToSHA[path] ?? "Cached-No-SHA" }
                sendNotifications(sha: shaForNotify, decision: .deny)
            }
            return
        }

        // Slow path — compute SHA outside the lock.
        if let sha = computeSHA(forPath: path) {
            let finalDecision: ExecDecision = mgr.stateLock.sync {
                if let expiry = mgr.tempAllowedSHAs[sha], expiry > Date() {
                    return .allow
                }
                return mgr.blockedSHAs.contains(sha) ? .deny : .allow
            }

            mgr.stateLock.perform {
                mgr.blockedPathToSHA[path] = sha
                mgr.decisionCache[path] = finalDecision
            }

            let authResult = (finalDecision == .allow) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
            es_respond_auth_result(client, message, authResult, false)

            if finalDecision == .deny {
                Logfile.es.log("Denied by SlowPath (SHA): \(path, privacy: .public)")
                sendNotifications(sha: sha, decision: .deny)
            }
            return

        } else {
            es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
            Logfile.es.log("Failed to compute SHA -> Denying: \(path, privacy: .public)")
            sendNotifications(sha: "Read-Error", decision: .deny)
            return
        }
    }
}
