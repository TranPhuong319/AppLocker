//
//  ESEventNotifyExec.swift
//  ESExtension
//
//  Created by Doe Phương on 31/7/26.
//

import Darwin
import EndpointSecurity
import Foundation
import os

extension ESManager {
    static func handleNotifyExec(client: OpaquePointer, message: ESMessage) {
        let messagePtr = message.pointee
        let targetPid = audit_token_to_pid(messagePtr.process.pointee.audit_token)

        guard targetPid > 0, let manager = ESManager.sharedInstanceForCallbacks else {
            return
        }

        guard let path = safePath(fromFilePointer: messagePtr.event.exec.target.pointee.executable) else {
            return
        }

        let parentPid = messagePtr.process.pointee.ppid
        let uid = audit_token_to_euid(messagePtr.process.pointee.audit_token)

        var signingID = "Unsigned/Unknown"
        let signingToken = messagePtr.event.exec.target.pointee.signing_id
        if let idStr = string(from: signingToken) {
            signingID = idStr
        }

        var targetProcess = messagePtr.event.exec.target.pointee
        let cdhashData = Data(bytes: &targetProcess.cdhash, count: 20)
        let cdhashHex = cdhashData.map { String(format: "%02x", $0) }.joined()

        guard manager.isProcessBlocked(path: path, cdhashData: cdhashData, cdhashHex: cdhashHex, uid: uid) else {
            return
        }

        let alreadyPending = manager.isPendingVerification(pid: targetPid)
        guard !alreadyPending else {
            Logfile.endpointSecurity.log("[NOTIFY_EXEC] PID \(targetPid) already pending (\(path))")
            return
        }

        // Mark PID pending FIRST (~10ns) so launchd's SIGCONT is denied on the very first attempt
        manager.markPendingVerification(pid: targetPid)
        let result = kill(targetPid, SIGSTOP)
        Logfile.endpointSecurity.log("Marked PID \(targetPid) as pending verification")

        if result == 0 {
            Logfile.endpointSecurity.log("[NOTIFY_EXEC] SIGSTOP sent to target PID \(targetPid) (\(path))")
        } else {
            Logfile.endpointSecurity.error("[NOTIFY_EXEC] SIGSTOP failed for PID \(targetPid): errno \(errno)")
        }

        let name = manager.computeAppName(forExecPath: path)
        let notification = BlockedNotification(
            name: name,
            path: path,
            cdhash: cdhashHex,
            parentPid: parentPid,
            uid: uid,
            signingID: signingID,
            targetPid: targetPid
        )
        manager.sendBlockedNotifications(notification: notification)
    }

    private func isProcessBlocked(path: String, cdhashData: Data, cdhashHex: String, uid: uid_t) -> Bool {
        let isZeroCDHash = cdhashData.allSatisfy { $0 == 0 }
        return stateLock.withLock { () -> Bool in
            if !isZeroCDHash {
                if lockedCDHashes.values.contains(where: { $0.contains(cdhashHex) }) {
                    return true
                }
            }
            return isPathInLockedBundle(path: path, uid: uid)
        }
    }

    private func isPathInLockedBundle(path: String, uid: uid_t) -> Bool {
        var url = URL(fileURLWithPath: path)
        let allPaths = lockedBundlePaths.values

        while url.pathComponents.count > 1 {
            let currentPath = url.path
            let stdPath = (currentPath as NSString).standardizingPath
            if allPaths.contains(where: { $0.contains(currentPath) || $0.contains(stdPath) }) {
                if let bundle = Bundle(url: url), let mainExec = bundle.executablePath {
                    let normPath = (path as NSString).standardizingPath
                    let normMainExec = (mainExec as NSString).standardizingPath
                    return normPath == normMainExec
                }
                return false
            }
            url.deleteLastPathComponent()
        }
        return false
    }

    func sendBlockedNotifications(notification: BlockedNotification) {
        DispatchQueue.global(qos: .userInteractive).async {
            TTYNotifier.notify(
                parentPid: notification.parentPid,
                blockedPath: notification.path,
                sha: notification.cdhash,
                identifier: notification.signingID
            )
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.sendBlockedNotificationToApp(notification: notification)
        }
    }
}


