//
//  ESEventAuthExec.swift
//  ESExtension
//
//  Created by Doe Phương on 2/1/26.
//

import EndpointSecurity
import Foundation
import os

extension ESManager {
    static func handleAuthExec(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let arrivalTime = Date()
        let messagePtr = message.pointee

        guard let path = safePath(fromFilePointer: messagePtr.event.exec.target.pointee.executable) else {
            Logfile.es.log("Missing exec path in AUTH_EXEC. Denying by default.")
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            return
        }

        guard let manager = ESManager.sharedInstanceForCallbacks else {
            Logfile.es.log("No ESManager instance. Denying exec.")
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            return
        }

        let parentPid = messagePtr.process.pointee.ppid
        var signingID = "Unsigned/Unknown"
        if let signingToken = messagePtr.event.exec.target.pointee.signing_id.data {
            signingID = String(cString: signingToken)
        }

        func sendNotifications(sha: String, decision: ExecDecision) {
            if decision == .deny {
                DispatchQueue.global(qos: .userInteractive).async {
                    TTYNotifier.notify(
                        parentPid: parentPid, blockedPath: path, sha: sha, identifier: signingID)
                }
                DispatchQueue.global(qos: .utility).async {
                    let name = manager.computeAppName(forExecPath: path)
                    manager.sendBlockedNotificationToApp(name: name, path: path, sha: sha)
                }
            }
        }

        // Fast path — single lock read of all state.
        let decisionResult: ExecDecision? = manager.stateLock.sync {
            if let mappedSHA = manager.blockedPathToSHA[path] {
                if let expiry = manager.tempAllowedSHAs[mappedSHA], expiry > Date() {
                    return .allow
                }
                if manager.blockedSHAs.contains(mappedSHA) {
                    return .deny
                }
            }
            if let cached = manager.decisionCache[path] {
                return cached
            }
            return nil
        }

        if let decision = decisionResult {
            let authResult = (decision == .allow) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
            // Use valve to safely respond
            _ = valve.respond(authResult, cache: false)  // NEVER cache to ensure locks work immediately

            if decision == .deny {
                Logfile.es.pLog("Denied by FastPath (Cache/Map): \(path)")
                let shaForNotify = manager.stateLock.sync {
                    manager.blockedPathToSHA[path] ?? "Cached-No-SHA"
                }
                sendNotifications(sha: shaForNotify, decision: .deny)
            }
            return
        }

        // Slow path — compute SHA outside the lock.
        // Limit concurrency to avoid CPU thrashing
        manager.shaSemaphore.wait()
        let sha = computeSHA(forPath: path)
        manager.shaSemaphore.signal()

        if let sha = sha {
            let finalDecision: ExecDecision = manager.stateLock.sync {
                if let expiry = manager.tempAllowedSHAs[sha], expiry > Date() {
                    return .allow
                }
                return manager.blockedSHAs.contains(sha) ? .deny : .allow
            }

            manager.stateLock.perform {
                manager.blockedPathToSHA[path] = sha
                manager.decisionCache[path] = finalDecision
            }

            let authResult = (finalDecision == .allow) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
            // Use valve to safely respond
            let elapsed = Date().timeIntervalSince(arrivalTime)
            if valve.respond(authResult, cache: false) { // NEVER cache ALLOW to ensure locks work immediately
                // Only log and notify if WE responded (not the timer)
                if finalDecision == .deny {
                    Logfile.es.pLog("Denied by SlowPath (SHA) in \(String(format: "%.2fs", elapsed)): \(path)")
                    sendNotifications(sha: sha, decision: .deny)
                } else {
                    // Logfile.es.pLog("Allowed by SlowPath (SHA) in \(String(format: "%.2fs", elapsed)): \(path)")
                }
            } else {
                Logfile.es.log("Late response for SHA in \(String(format: "%.2fs", elapsed)): \(path) (Timer won)")
            }
            return

        } else {
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            Logfile.es.pLog("Failed to compute SHA -> Denying: \(path)")
            sendNotifications(sha: "Read-Error", decision: .deny)
            return
        }
    }
}
