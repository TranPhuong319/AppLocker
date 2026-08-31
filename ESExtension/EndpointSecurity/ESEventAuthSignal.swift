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

        let isPending = isPendingVerification(pid: targetPid)

        if isPending && sig == SIGCONT {
            let isAuthorizedSender = stateLock.withLock {
                return senderPid == authenticatedMainAppPID || senderPid == getpid()
            }

            if !isAuthorizedSender {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                Logfile.endpointSecurity.warning(
                    """
                    [AuthSignal] SECURITY SHIELD: Denied SIGCONT from PID \(senderPid, privacy: .public) \
                    to pending PID \(targetPid, privacy: .public)
                    """
                )
                return
            }
        }

        _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
    }
}
