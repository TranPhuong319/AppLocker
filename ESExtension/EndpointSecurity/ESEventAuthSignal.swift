//
//  ESEventAuthSignal.swift
//  ESExtension
//
//  Created by Doe Phương on 31/7/26.
//

import Darwin
import EndpointSecurity
import Foundation
import os

struct SignalEventContext: Sendable {
    let targetPID: pid_t
    let targetAuditToken: audit_token_t
    let senderPID: pid_t
    let senderExecutablePath: String?
    let senderResponsibleAuditToken: audit_token_t?
    let sig: Int32

    init(
        targetPID: pid_t,
        targetAuditToken: audit_token_t,
        senderPID: pid_t,
        senderExecutablePath: String? = nil,
        senderResponsibleAuditToken: audit_token_t? = nil,
        sig: Int32
    ) {
        self.targetPID = targetPID
        self.targetAuditToken = targetAuditToken
        self.senderPID = senderPID
        self.senderExecutablePath = senderExecutablePath
        self.senderResponsibleAuditToken = senderResponsibleAuditToken
        self.sig = sig
    }
}

extension ESManager {
    func handleAuthSignal(client: OpaquePointer, message: ESMessage, valve: ESSafetyValve) {
        let messagePtr = message.pointee
        let targetToken = messagePtr.event.signal.target.pointee.audit_token
        let targetPid = audit_token_to_pid(targetToken)
        let processPtr = messagePtr.process.pointee
        let senderPid = audit_token_to_pid(processPtr.audit_token)
        let sig = messagePtr.event.signal.sig

        let context = SignalEventContext(
            targetPID: targetPid,
            targetAuditToken: targetToken,
            senderPID: senderPid,
            senderExecutablePath: safePath(fromFilePointer: processPtr.executable),
            senderResponsibleAuditToken: processPtr.responsible_audit_token,
            sig: sig
        )
        evaluateAuthSignal(context: context, valve: valve)
    }

    func evaluateAuthSignal(context: SignalEventContext, valve: any ESAuthResponding) {
        let targetPid = context.targetPID
        let senderPid = context.senderPID
        let sig = context.sig

        let pendingEntry = pendingPIDLock.withLock {
            pendingVerificationProcesses[targetPid]
        }

        if let expectedRecord = pendingEntry, sig == SIGCONT {
            let targetToken = context.targetAuditToken
            let expectedVersion = audit_token_to_pidversion(expectedRecord.token)
            let currentVersion = audit_token_to_pidversion(targetToken)

            // Strict Fail-Deny: If PID recycling or version mismatch detected, DENY immediately
            guard expectedVersion == currentVersion else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                Logfile.endpointSecurity.fault(
                    """
                    [AuthSignal] PID RECYCLING / VERSION MISMATCH for target PID \(targetPid, privacy: .public)! \
                    Expected: \(expectedVersion, privacy: .public), target: \(currentVersion, privacy: .public). \
                    Denied SIGCONT.
                    """
                )
                return
            }

            let isAuthorizedSender = (senderPid == getpid())

            if !isAuthorizedSender {
                handleUnauthorizedSignal(
                    context: context,
                    targetAppName: expectedRecord.notification.name,
                    valve: valve
                )
                return
            }
        }

        _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
    }

    private func handleUnauthorizedSignal(
        context: SignalEventContext,
        targetAppName: String,
        valve: any ESAuthResponding
    ) {
        let targetPid = context.targetPID
        let senderPid = context.senderPID
        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        let senderPath = context.senderExecutablePath
            ?? processPath(for: senderPid)
            ?? "PID \(senderPid)"

        let isLaunchMachinery = senderPath.hasSuffix("/launchservicesd") || senderPath.hasSuffix("/launchd")
        if isLaunchMachinery {
            Logfile.endpointSecurity.debug(
                """
                [AuthSignal] Denied launch machinery SIGCONT from \(senderPath, privacy: .public) \
                to pending PID \(targetPid, privacy: .public)
                """
            )
            return
        }

        let responsiblePid = context.senderResponsibleAuditToken.map { audit_token_to_pid($0) } ?? 0
        let responsiblePath = processPath(for: responsiblePid)
        let senderDisplayName: String = {
            if let respPath = responsiblePath, respPath.contains(".app") {
                return self.computeAppName(forExecPath: respPath)
            }
            if senderPath.starts(with: "/") {
                return self.computeAppName(forExecPath: senderPath)
            }
            return senderPath
        }()

        let responsiblePathArg = responsiblePath ?? ""
        Logfile.endpointSecurity.warning(
            """
            [SecurityEvent:TamperBlocked] Target: \(targetAppName, privacy: .public) \
            (PID \(targetPid, privacy: .public)) | Sender: \(senderDisplayName, privacy: .public) \
            (PID \(senderPid, privacy: .public)) | SenderPath: \(senderPath, privacy: .public) \
            | ResponsiblePath: \(responsiblePathArg, privacy: .public)
            """
        )
    }
}
