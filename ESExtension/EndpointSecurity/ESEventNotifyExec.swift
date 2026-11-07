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

struct ExecEventContext: Sendable {
    let targetPID: pid_t
    let targetAuditToken: audit_token_t
    let parentPID: pid_t
    let uid: uid_t
    let path: String
    let signingID: String
    let cdhashData: Data
    let cdhashHex: String

    init(
        targetPID: pid_t,
        targetAuditToken: audit_token_t,
        parentPID: pid_t = getpid(),
        uid: uid_t = getuid(),
        path: String,
        signingID: String = "Unsigned/Unknown",
        cdhashData: Data = Data(repeating: 0, count: 20),
        cdhashHex: String? = nil
    ) {
        self.targetPID = targetPID
        self.targetAuditToken = targetAuditToken
        self.parentPID = parentPID
        self.uid = uid
        self.path = path
        self.signingID = signingID
        self.cdhashData = cdhashData
        self.cdhashHex = cdhashHex ?? cdhashData.hexEncodedString
    }
}

extension ESManager {
    func handleNotifyExec(client: OpaquePointer, message: ESMessage) {
        let messagePtr = message.pointee
        let targetPid = audit_token_to_pid(messagePtr.event.exec.target.pointee.audit_token)
        guard targetPid > 0,
              let path = safePath(fromFilePointer: messagePtr.event.exec.target.pointee.executable) else {
            return
        }

        let token = messagePtr.event.exec.target.pointee.audit_token
        let signingID = string(from: messagePtr.event.exec.target.pointee.signing_id) ?? "Unsigned/Unknown"
        let parentPid = messagePtr.process.pointee.ppid
        let uid = audit_token_to_euid(token)
        var targetProcess = messagePtr.event.exec.target.pointee
        let cdhashData = Data(bytes: &targetProcess.cdhash, count: 20)
        let cdhashHex = cdhashData.hexEncodedString

        let context = ExecEventContext(
            targetPID: targetPid,
            targetAuditToken: token,
            parentPID: parentPid,
            uid: uid,
            path: path,
            signingID: signingID,
            cdhashData: cdhashData,
            cdhashHex: cdhashHex
        )

        evaluateNotifyExec(context: context, rawMessage: message)
    }

    @discardableResult
    func evaluateNotifyExec(context: ExecEventContext, rawMessage: ESMessage? = nil) -> Bool {
        let targetPid = context.targetPID
        guard targetPid > 0 else { return false }

        let token = context.targetAuditToken
        let signingID = context.signingID
        if isAppLockerSelfExecution(signingID: signingID, token: token, pid: targetPid) {
            return false
        }

        let path = context.path
        let uid = context.uid
        let cdhashData = context.cdhashData
        let cdhashHex = context.cdhashHex

        guard isProcessBlocked(
            path: path,
            cdhashData: cdhashData,
            cdhashHex: cdhashHex,
            signingID: signingID,
            uid: uid
        ) else {
            return false
        }

        let name = computeAppName(forExecPath: path)
        if let rawMessage {
            logOriginTrace(name: name, message: rawMessage)
        }

        if isAllowedIncomingCall(signingID: signingID, path: path, uid: uid) {
            Logfile.endpointSecurity.notice(
                """
                [NotifyExec] Allowed incoming call execution for \(name, privacy: .public) \
                (PID \(targetPid, privacy: .public))
                """
            )
            return false
        }

        let notification = BlockedNotification(
            name: name,
            path: path,
            cdhash: cdhashHex,
            parentPid: context.parentPID,
            uid: uid,
            signingID: signingID,
            targetPid: targetPid
        )
        suspendAndNotifyBlockedProcess(notification: notification, targetPid: targetPid, token: token)
        return true
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

        Logfile.endpointSecurity.debug(
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

        guard kill(targetPid, 0) == 0 else { return }

        // Mark PID pending FIRST (~10ns) so launchd's SIGCONT is denied on the very first attempt
        markPendingVerification(pid: targetPid, token: token, notification: notification)
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
            sendBlockedNotifications(notification: notification)
        } else {
            removePendingVerification(pid: targetPid)
            Logfile.endpointSecurity.warning(
                """
                [NotifyExec] SIGSTOP failed for PID \(targetPid, privacy: .public): \
                errno \(errno, privacy: .public). Rolled back pending state.
                """
            )
        }
    }

    func sendBlockedNotifications(notification: BlockedNotification) {
        if !isTesting {
            Task.detached(priority: .high) {
                TTYNotifier.notify(
                    targetPid: notification.targetPid,
                    parentPid: notification.parentPid,
                    blockedPath: notification.path,
                    cdhash: notification.cdhash,
                    identifier: notification.signingID
                )
            }
        }
        Task.detached(priority: .low) { [weak self] in
            self?.sendBlockedNotificationToApp(notification: notification)
        }
    }
}
