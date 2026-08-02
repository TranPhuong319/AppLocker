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
    static func handleAuthSignal(client: OpaquePointer, message: ESMessage, valve: ESSafetyValve) {
        let messagePtr = message.pointee
        let targetPid = audit_token_to_pid(messagePtr.event.signal.target.pointee.audit_token)
        let senderPid = audit_token_to_pid(messagePtr.process.pointee.audit_token)
        let sig = messagePtr.event.signal.sig

        guard let manager = ESManager.sharedInstanceForCallbacks else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            return
        }

        let isPending = manager.isPendingVerification(pid: targetPid)

        if isPending {
            let isAuthorizedSender = manager.stateLock.sync {
                return senderPid == manager.authenticatedMainAppPID || senderPid == getpid()
            }

            if !isAuthorizedSender {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                Logfile.endpointSecurity.log(
                    "[AUTH_SIGNAL] SECURITY SHIELD: Denied sig \(sig) from PID \(senderPid) to pending PID \(targetPid)"
                )
                return
            }
        }

        _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
    }
}
