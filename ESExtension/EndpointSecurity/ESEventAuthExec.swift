//
//  ESEventAuthExec.swift
//  ESExtension
//
//  Created by Doe Phương on 2/1/26.
//

import EndpointSecurity
import Foundation
import Darwin
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
            Logfile.endpointSecurity.log("Missing exec path in AUTH_EXEC. Denying by default.")
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            return
        }

        guard let manager = ESManager.sharedInstanceForCallbacks else {
            Logfile.endpointSecurity.log("No ESManager instance. Denying exec.")
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            return
        }

        let parentPid = messagePtr.process.pointee.ppid
        let uid = audit_token_to_euid(messagePtr.process.pointee.audit_token)
        
        var signingID = "Unsigned/Unknown"
        if let signingToken = messagePtr.event.exec.target.pointee.signing_id.data {
            signingID = String(cString: signingToken)
        }

        // 1. Fast path check
        if let decision = manager.getFastPathDecision(path: path, uid: uid) {
            let authResult = (decision == .allow) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY

            if decision == .deny {
                manager.applyDenyDelay(deadline: messagePtr.deadline)
            }

            _ = valve.respond(authResult, cache: false)

            if decision == .deny {
                Logfile.endpointSecurity.log("Denied by FastPath (Cache/Map): \(path)")
                let shaForNotify = manager.stateLock.sync { manager.blockedPathToSHA[path] ?? "Cached-No-SHA" }
                manager.sendBlockedNotifications(path: path, sha: shaForNotify, parentPid: parentPid, uid: uid, signingID: signingID)
            }
            return
        }

        // 2. Slow path check
        manager.handleSlowPath(
            path: path,
            message: message,
            valve: valve,
            context: SlowPathContext(arrivalTime: arrivalTime, parentPid: parentPid, uid: uid, signingID: signingID)
        )
    }

    // MARK: - Helper Methods

    private func getFastPathDecision(path: String, uid: uid_t) -> ExecDecision? {
        return stateLock.sync {
            if let mappedSHA = blockedPathToSHA[path] {
                if let expiry = tempAllowedSHAs[mappedSHA], expiry > Date() {
                    return .allow
                }
                if let userBlockedSHAs = blockedSHAs[uid], userBlockedSHAs.contains(mappedSHA) {
                    return .deny
                }
            }
            return decisionCache[path]
        }
    }

    private struct SlowPathContext {
        let arrivalTime: Date
        let parentPid: pid_t
        let uid: uid_t
        let signingID: String
    }

    private func handleSlowPath(
        path: String,
        message: ESMessage,
        valve: ESSafetyValve,
        context: SlowPathContext
    ) {
        let remainingSeconds = ESManager.getRemainingSeconds(fromDeadline: message.pointee.deadline)
        let requiredTime: TimeInterval = 1.1 // 0.1s processing + 1.0s buffer

        var sha: String?
        if remainingSeconds >= requiredTime {
            shaSemaphore.wait()
            defer { shaSemaphore.signal() }
            sha = computeSHA(forPath: path)
        } else {
            Logfile.endpointSecurity.log("Skipping SHA calc: Not enough budget (Has: \(String(format: "%.2f", remainingSeconds))s, Need: \(requiredTime)s)")
        }

        guard let finalSHA = sha else {
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            Logfile.endpointSecurity.log("Failed to compute SHA -> Denying: \(path)")
            sendBlockedNotifications(
                path: path, sha: "Read-Error",
                parentPid: context.parentPid, uid: context.uid, signingID: context.signingID
            )
            return
        }

        let finalDecision: ExecDecision = stateLock.sync {
            if let expiry = tempAllowedSHAs[finalSHA], expiry > Date() {
                return .allow
            }
            if let userBlockedSHAs = blockedSHAs[context.uid], userBlockedSHAs.contains(finalSHA) {
                return .deny
            }
            return .allow
        }

        stateLock.perform {
            blockedPathToSHA[path] = finalSHA
            decisionCache[path] = finalDecision
        }

        let authResult = (finalDecision == .allow) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
        let elapsed = Date().timeIntervalSince(context.arrivalTime)

        if valve.respond(authResult, cache: false) {
            if finalDecision == .deny {
                Logfile.endpointSecurity.log("Denied by SlowPath (SHA) in \(String(format: "%.2fs", elapsed)): \(path)")
                sendBlockedNotifications(
                    path: path, sha: finalSHA,
                    parentPid: context.parentPid, uid: context.uid, signingID: context.signingID
                )
            }
        } else {
            Logfile.endpointSecurity.log("Late response for SHA in \(String(format: "%.2fs", elapsed)): \(path) (Timer won)")
        }
    }

    private func applyDenyDelay(deadline: UInt64) {
        let remainingSeconds = ESManager.getRemainingSeconds(fromDeadline: deadline)
        let targetDelay: TimeInterval = 0.2
        let safetyBuffer: TimeInterval = 1.0

        let availableSleep = max(0, remainingSeconds - safetyBuffer)
        let actualDelay = min(targetDelay, availableSleep)

        if actualDelay > 0.01 {
            Thread.sleep(forTimeInterval: actualDelay)
        }
    }

    private func sendBlockedNotifications(path: String, sha: String, parentPid: pid_t, uid: uid_t, signingID: String) {
        DispatchQueue.global(qos: .userInteractive).async {
            TTYNotifier.notify(parentPid: parentPid, blockedPath: path, sha: sha, identifier: signingID)
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let name = self.computeAppName(forExecPath: path)
            self.sendBlockedNotificationToApp(name: name, path: path, sha: sha, uid: uid)
        }
    }

    static func getRemainingSeconds(fromDeadline deadline: UInt64) -> TimeInterval {
        let now = mach_absolute_time()
        guard deadline > now else { return 0 }

        let remainingTicks = deadline - now
        let remainingNanos = ESManager.machTimeToNanos(remainingTicks)
        return TimeInterval(remainingNanos) / 1_000_000_000
    }
}
