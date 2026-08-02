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

struct BlockedExecContext {
    let path: String
    let cdhash: String
    let parentPid: pid_t
    let uid: uid_t
    let signingID: String
    let targetPid: pid_t
}

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

        var targetProcess = messagePtr.event.exec.target.pointee
        let cdhashData = Data(bytes: &targetProcess.cdhash, count: 20)
        let cdhashHex = cdhashData.map { String(format: "%02x", $0) }.joined()
        let isZeroCDHash = cdhashData.allSatisfy { $0 == 0 }

        let isBlocked = manager.stateLock.sync { () -> Bool in
            if !isZeroCDHash {
                let userCDHashes = manager.lockedCDHashes[uid] ?? Set<String>()
                let allHashes = manager.lockedCDHashes.values
                if userCDHashes.contains(cdhashHex) || allHashes.contains(where: { $0.contains(cdhashHex) }) {
                    return true
                }
            }
            return manager.isPathInLockedBundle(path: path, uid: uid)
        }

        if isBlocked {
            manager.interceptAndSuspend(
                path: path,
                cdhash: cdhashHex,
                parentPid: parentPid,
                uid: uid,
                signingID: signingID
            )
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            Logfile.endpointSecurity.log("[AUTH_EXEC] Intercepted 0ms (cdhash/path) -> Marked Pending: \(path)")
        } else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
        }
    }

    private func isPathInLockedBundle(path: String, uid: uid_t) -> Bool {
        guard !path.isAppExtensionOrPlugin else { return false }
        var url = URL(fileURLWithPath: path)
        let userBundlePaths = lockedBundlePaths[uid] ?? Set<String>()
        let allPaths = lockedBundlePaths.values

        while url.pathComponents.count > 1 {
            let currentPath = url.path
            let stdPath = (currentPath as NSString).standardizingPath
            if userBundlePaths.contains(currentPath) || userBundlePaths.contains(stdPath) ||
               allPaths.contains(where: { $0.contains(currentPath) || $0.contains(stdPath) }) {
                return true
            }
            if url.pathExtension == "app" { break }
            url.deleteLastPathComponent()
        }
        return false
    }

    // MARK: - Helper Methods

    func interceptAndSuspend(path: String, cdhash: String, parentPid: pid_t, uid: uid_t, signingID: String) {
        markPendingVerificationPath(path: path, cdhash: cdhash, parentPid: parentPid, uid: uid, signingID: signingID)
        Logfile.endpointSecurity.log("[AUTH_EXEC] Marked pending path: \(path)")
    }

    func sendBlockedNotifications(context: BlockedExecContext) {
        DispatchQueue.global(qos: .userInteractive).async {
            TTYNotifier.notify(
                parentPid: context.parentPid,
                blockedPath: context.path,
                sha: context.cdhash,
                identifier: context.signingID
            )
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let name = self.computeAppName(forExecPath: context.path)
            self.sendBlockedNotificationToApp(
                name: name,
                path: context.path,
                cdhash: context.cdhash,
                uid: context.uid,
                targetPid: context.targetPid
            )
        }
    }
}
