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
import Security

extension ESManager {
    func handleNotifyExec(client: OpaquePointer, message: ESMessage) {
        let messagePtr = message.pointee
        let targetPid = audit_token_to_pid(messagePtr.event.exec.target.pointee.audit_token)

        guard targetPid > 0 else {
            return
        }

        guard let path = safePath(
            fromFilePointer: messagePtr.event.exec.target.pointee.executable
        ) else {
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

        guard isProcessBlocked(path: path, cdhashData: cdhashData, cdhashHex: cdhashHex, uid: uid) else {
            return
        }

        let name = computeAppName(forExecPath: path)
        logOriginTrace(name: name, message: message)

        if isAllowedIncomingCall(signingID: signingID, path: path, uid: uid) {
            Logfile.endpointSecurity.notice(
                """
                [NotifyExec] Allowed incoming call execution for \(name, privacy: .public) \
                (PID \(targetPid, privacy: .public))
                """
            )
            return
        }

        let notification = BlockedNotification(
            name: name,
            path: path,
            cdhash: cdhashHex,
            parentPid: parentPid,
            uid: uid,
            signingID: signingID,
            targetPid: targetPid
        )

        suspendAndNotifyBlockedProcess(
            notification: notification,
            targetPid: targetPid,
            token: messagePtr.event.exec.target.pointee.audit_token
        )
    }

    private func logOriginTrace(name: String, message: ESMessage) {
        let target = message.pointee.event.exec.target.pointee
        let targetPid = audit_token_to_pid(target.audit_token)
        let targetPpid = target.ppid
        let parentPid = audit_token_to_pid(target.parent_audit_token)
        let responsiblePid = audit_token_to_pid(target.responsible_audit_token)
        let parentPath = processPath(for: parentPid) ?? "none"
        let responsiblePath = processPath(for: responsiblePid) ?? "none"

        let caller = message.pointee.process.pointee
        let callerPid = audit_token_to_pid(caller.audit_token)
        let callerPpid = caller.ppid
        let callerResponsiblePid = audit_token_to_pid(caller.responsible_audit_token)
        let callerPath = safePath(fromFilePointer: caller.executable) ?? "none"
        let callerResponsiblePath = processPath(for: callerResponsiblePid) ?? "none"

        let args = withUnsafePointer(to: message.rawMessage.pointee.event.exec) { execArguments(for: $0) }
        let argsSummary = args.joined(separator: " ")

        Logfile.endpointSecurity.notice(
            """
            [NotifyExec] Origin trace for \(name, privacy: .public) (PID \(targetPid, privacy: .public)):
              ├─ Target PPID: \(targetPpid, privacy: .public)
              ├─ Parent: PID=\(parentPid, privacy: .public) (\(parentPath, privacy: .public))
              ├─ Responsible: PID=\(responsiblePid, privacy: .public) (\(responsiblePath, privacy: .public))
              ├─ Caller: PID=\(callerPid, privacy: .public) (\(callerPath, privacy: .public))
              ├─ Caller PPID: \(callerPpid, privacy: .public)
              ├─ Caller Resp: PID=\(callerResponsiblePid, privacy: .public) (\(callerResponsiblePath, privacy: .public))
              └─ Args: [\(argsSummary, privacy: .public)]
            """
        )
    }

    private func suspendAndNotifyBlockedProcess(
        notification: BlockedNotification,
        targetPid: pid_t,
        token: audit_token_t
    ) {
        let alreadyPending = isPendingVerification(pid: targetPid)
        guard !alreadyPending else {
            Logfile.endpointSecurity.debug(
                """
                [NotifyExec] PID \(targetPid, privacy: .public) already pending \
                (\(notification.path, privacy: .public))
                """
            )
            return
        }

        // Mark PID pending FIRST (~10ns) so launchd's SIGCONT is denied on the very first attempt
        markPendingVerification(pid: targetPid, token: token)
        let result = kill(targetPid, SIGSTOP)
        let version = audit_token_to_pidversion(token)
        Logfile.endpointSecurity.debug(
            """
            [NotifyExec] Marked PID \(targetPid, privacy: .public) (version: \(version, privacy: .public)) \
            as pending verification
            """
        )

        if result == 0 {
            Logfile.endpointSecurity.info(
                """
                [NotifyExec] SIGSTOP sent to target PID \(targetPid, privacy: .public) \
                (\(notification.path, privacy: .public))
                """
            )
        } else {
            Logfile.endpointSecurity.error(
                """
                [NotifyExec] SIGSTOP failed for PID \(targetPid, privacy: .public): \
                errno \(errno, privacy: .public)
                """
            )
        }

        sendBlockedNotifications(notification: notification)
    }

    private func isProcessBlocked(path: String, cdhashData: Data, cdhashHex: String, uid: uid_t) -> Bool {
        let isZeroCDHash = cdhashData.allSatisfy { $0 == 0 }
        return stateLock.withLock { () -> Bool in
            if !isZeroCDHash, let userCDHashes = lockedCDHashes[uid], userCDHashes.contains(cdhashHex) {
                return true
            }
            return isPathInLockedBundle(path: path, uid: uid)
        }
    }

    private func isPathInLockedBundle(path: String, uid: uid_t) -> Bool {
        guard let userBundlePaths = lockedBundlePaths[uid], !userBundlePaths.isEmpty else { return false }
        var url = URL(fileURLWithPath: path)

        while url.pathComponents.count > 1 {
            let currentPath = url.path
            let stdPath = (currentPath as NSString).standardizingPath
            if userBundlePaths.contains(currentPath) || userBundlePaths.contains(stdPath) {
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
        Task.detached(priority: .high) {
            TTYNotifier.notify(
                targetPid: notification.targetPid,
                parentPid: notification.parentPid,
                blockedPath: notification.path,
                cdhash: notification.cdhash,
                identifier: notification.signingID
            )
        }
        Task.detached(priority: .low) { [weak self] in
            self?.sendBlockedNotificationToApp(notification: notification)
        }
    }

    private func isAllowedIncomingCall(
        signingID: String,
        path: String,
        uid: uid_t
    ) -> Bool {
        let isTelephonyApp = signingID == "com.apple.FaceTime" || signingID == "com.apple.mobilephone"
            || path.contains("/FaceTime.app/") || path.contains("/Phone.app/")
        guard isTelephonyApp else { return false }

        let (userAllowsIncoming, isRinging) = stateLock.withLock {
            (self.allowIncomingCallsByUID[uid] ?? true, self.isIncomingCallActive)
        }
        guard userAllowsIncoming else { return false }

        let isCallActive = isRinging || isSharingActivityLevelPhoneCall()
        guard isCallActive else { return false }

        return isValidAppleTelephonyBinary(path: path)
    }

    private func isSharingActivityLevelPhoneCall() -> Bool {
        var token: Int32 = 0
        guard notify_register_check("com.apple.sharing.activity-level-changed", &token) == NOTIFY_STATUS_OK else {
            return false
        }
        defer { notify_cancel(token) }

        var state: UInt64 = 0
        guard notify_get_state(token, &state) == NOTIFY_STATUS_OK else {
            return false
        }

        Logfile.endpointSecurity.debug(
            "[NotifyExec] com.apple.sharing.activity-level-changed state: \(state, privacy: .public)"
        )

        return state == 14
    }

    private func isValidAppleTelephonyBinary(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }

        let reqString = "anchor apple and (identifier \"com.apple.mobilephone\" or identifier \"com.apple.FaceTime\")"
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(reqString as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else { return false }

        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }
}
