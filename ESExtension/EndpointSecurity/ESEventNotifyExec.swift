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
        // In NOTIFY_EXEC, message.process IS the newly exec'd process (real PID, always > 0)
        let targetPid = audit_token_to_pid(messagePtr.process.pointee.audit_token)

        guard targetPid > 0, let manager = ESManager.sharedInstanceForCallbacks else {
            return
        }

        guard let path = safePath(fromFilePointer: messagePtr.event.exec.target.pointee.executable) else {
            return
        }

        if let info = manager.peekPendingVerificationInfo(forPath: path) {
            let alreadyPending = manager.isPendingVerification(pid: targetPid)
            if !alreadyPending {
                // Mark PID pending FIRST (~10ns) so launchd's SIGCONT is denied on the very first attempt
                manager.markPendingVerification(pid: targetPid)
                let result = kill(targetPid, SIGSTOP)
                Logfile.endpointSecurity.log("Marked PID \(targetPid) as pending verification")
                if result == 0 {
                    Logfile.endpointSecurity.log(
                        "[NOTIFY_EXEC] SIGSTOP sent to target PID \(targetPid) (\(path))"
                    )
                } else {
                    Logfile.endpointSecurity.error(
                        "[NOTIFY_EXEC] SIGSTOP failed for PID \(targetPid): errno \(errno)"
                    )
                }
                manager.sendBlockedNotifications(
                    context: BlockedExecContext(
                        path: path,
                        cdhash: info.cdhash,
                        parentPid: info.parentPid,
                        uid: info.uid,
                        signingID: info.signingID,
                        targetPid: targetPid
                    )
                )
            } else {
                Logfile.endpointSecurity.log("[NOTIFY_EXEC] PID \(targetPid) already pending (\(path))")
            }
        }
    }
}
