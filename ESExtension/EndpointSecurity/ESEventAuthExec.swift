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

        // 1. Extract cdhash from ES message target (0ms latency)
        var targetProcess = messagePtr.event.exec.target.pointee
        let cdhashData = Data(bytes: &targetProcess.cdhash, count: 20)
        let cdhashHex = cdhashData.map { String(format: "%02x", $0) }.joined()
        let isZeroCDHash = cdhashData.allSatisfy { $0 == 0 }

        // 2. Locklist Matching (cdhash & .app Bundle Path)
        let isBlocked = manager.stateLock.sync { () -> Bool in
            if !isZeroCDHash {
                let userCDHashes = manager.lockedCDHashes[uid] ?? Set<String>()
                if userCDHashes.contains(cdhashHex) || manager.lockedCDHashes.values.contains(where: { $0.contains(cdhashHex) }) {
                    return true
                }
            }

            // Bundle path matching (.app fallback for sub-processes/helpers)
            // ponytail: Skip app extensions (.appex) and helper services (.xpc) in PlugIns / XPCServices to prevent blocking background widgets
            if !path.isAppExtensionOrPlugin {
                var url = URL(fileURLWithPath: path)
                let userBundlePaths = manager.lockedBundlePaths[uid] ?? Set<String>()

                while url.pathComponents.count > 1 {
                    let currentPath = url.path
                    let stdPath = (currentPath as NSString).standardizingPath
                    if userBundlePaths.contains(currentPath) || userBundlePaths.contains(stdPath) ||
                       manager.lockedBundlePaths.values.contains(where: { $0.contains(currentPath) || $0.contains(stdPath) }) {
                        return true
                    }
                    if url.pathExtension == "app" {
                        break
                    }
                    url.deleteLastPathComponent()
                }
            }
            return false
        }

        // 3. Execution Decision
        if isBlocked {
            manager.interceptAndSuspend(path: path, cdhash: cdhashHex, parentPid: parentPid, uid: uid, signingID: signingID)
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            Logfile.endpointSecurity.log("[AUTH_EXEC] Intercepted 0ms (cdhash/path) -> Marked Pending: \(path)")
        } else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
        }
    }

    // MARK: - Helper Methods

    func interceptAndSuspend(path: String, cdhash: String, parentPid: pid_t, uid: uid_t, signingID: String) {
        // AUTH_EXEC: kernel has not created the process yet, PID = 0.
        // Mark the path as pending — NOTIFY_EXEC will SIGSTOP + notify with the real PID.
        markPendingVerificationPath(path: path, cdhash: cdhash, parentPid: parentPid, uid: uid, signingID: signingID)
        Logfile.endpointSecurity.log("[AUTH_EXEC] Marked pending path: \(path)")
    }

    func sendBlockedNotifications(path: String, cdhash: String, parentPid: pid_t, uid: uid_t, signingID: String, targetPid: pid_t) {
        DispatchQueue.global(qos: .userInteractive).async {
            TTYNotifier.notify(parentPid: parentPid, blockedPath: path, sha: cdhash, identifier: signingID)
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let name = self.computeAppName(forExecPath: path)
            self.sendBlockedNotificationToApp(name: name, path: path, cdhash: cdhash, uid: uid, targetPid: targetPid)
        }
    }
}
