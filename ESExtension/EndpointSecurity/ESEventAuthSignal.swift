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

extension ESManager {
    func handleAuthSignal(client: OpaquePointer, message: ESMessage, valve: ESSafetyValve) {
        let messagePtr = message.pointee
        let targetPid = audit_token_to_pid(messagePtr.event.signal.target.pointee.audit_token)
        let senderPid = audit_token_to_pid(messagePtr.process.pointee.audit_token)
        let sig = messagePtr.event.signal.sig

        let pendingEntry = pendingPIDLock.withLock {
            pendingVerificationProcesses[targetPid]
        }

        if let expectedRecord = pendingEntry, sig == SIGCONT {
            let targetToken = messagePtr.event.signal.target.pointee.audit_token
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
                    message: message,
                    targetPid: targetPid,
                    targetAppName: expectedRecord.notification.name,
                    senderPid: senderPid,
                    valve: valve
                )
                return
            }
        }

        _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
    }

    private func handleUnauthorizedSignal(
        message: ESMessage,
        targetPid: pid_t,
        targetAppName: String,
        senderPid: pid_t,
        valve: ESSafetyValve
    ) {
        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        let processPtr = message.pointee.process.pointee
        let senderPath = safePath(fromFilePointer: processPtr.executable)
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

        let responsiblePid = audit_token_to_pid(processPtr.responsible_audit_token)
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

        Logfile.endpointSecurity.warning(
            """
            [SecurityEvent:TamperBlocked] Target: \(targetAppName, privacy: .public) \
            (PID \(targetPid, privacy: .public)) | Sender: \(senderDisplayName, privacy: .public) \
            (PID \(senderPid, privacy: .public)) | SenderPath: \(senderPath, privacy: .public)
            """
        )
    }
}
