//
//  ESEventNotifyExit.swift
//  ESExtension
//
//  Created by Doe Phương on 7/2/26.
//

import EndpointSecurity
import Foundation
import os

struct ExitEventContext: Sendable {
    let exitingPID: pid_t
    let exitingUID: uid_t
    let isMainApp: Bool
    let exitStat: Int32
}

extension ESManager {
    func handleNotifyExit(client: OpaquePointer, message: ESMessage) {
        let process = message.pointee.process
        let exitingPID = audit_token_to_pid(process.pointee.audit_token)
        let exitingUID = audit_token_to_euid(process.pointee.audit_token)
        let context = ExitEventContext(
            exitingPID: exitingPID,
            exitingUID: exitingUID,
            isMainApp: isMainAppProcess(process),
            exitStat: message.pointee.event.exit.stat
        )
        evaluateNotifyExit(context: context)
    }

    func evaluateNotifyExit(context: ExitEventContext) {
        notifyPendingProcessExitIfNeeded(pid: context.exitingPID, uid: context.exitingUID)

        guard context.isMainApp else { return }
        handleMainAppExit(pid: context.exitingPID, exitStat: context.exitStat)
    }

    private func notifyPendingProcessExitIfNeeded(pid: pid_t, uid: uid_t) {
        guard removePendingVerification(pid: pid), pid > 0 else { return }
        if let conn = pickAppConnection(forUID: uid) ?? pickAppConnection(),
           let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
               Logfile.esXPC.error("[ESExit] XPC notifyProcessExited error: \(String(describing: error))")
           }) as? ESXPCProtocol {
            proxy.notifyProcessExited(pid: Int32(pid))
            Logfile.esXPC.debug("[ESExit] Notified app about exited pending PID: \(pid, privacy: .public)")
        }
    }

    private func handleMainAppExit(pid: pid_t, exitStat: Int32) {
        processIDLock.withLock {
            if self.authenticatedMainAppPID == pid {
                self.authenticatedMainAppPID = nil
                self.authenticatedMainAppPIDVersion = nil
            }
            if self.lastKnownMainAppPID == pid {
                self.lastKnownMainAppPID = nil
            }
        }
        Logfile.endpointSecurity.info("[Guardian] Main App (PID: \(pid, privacy: .public)) exited.")

        if exitStat == 0 {
            Logfile.endpointSecurity.info(
                "[Guardian] Shutdown was clean (stat: \(exitStat, privacy: .public)). Watchdog standing down."
            )
            return
        }

        scheduleGuardianWatchdog(stat: exitStat)
    }

    private func scheduleGuardianWatchdog(stat: Int32) {
        Logfile.endpointSecurity.warning(
            """
            [Guardian] Unexpected Main App termination detected (stat: \(stat, privacy: .public))! \
            Launching watchdog (10s delay)...
            """
        )

        let uid = stateLock.withLock { activeUserUID }
        guard let userUID = uid else {
            Logfile.endpointSecurity.error("[Guardian] No active User UID found. Cannot kickstart.")
            return
        }

        let delay = guardianWatchdogDelay
        let restarter = guardianAgentRestarter ?? { AppLauncherUtils.forceEnableAndRestartAgent(for: $0) }

        Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            Logfile.endpointSecurity.debug("[Guardian] Watchdog checking if Main App has recovered...")

            let isAppRunning = self.processIDLock.withLock { self.authenticatedMainAppPID != nil }
            if isAppRunning {
                Logfile.endpointSecurity.info("[Guardian] Main App recovered via launchd. Watchdog cancelled.")
            } else {
                Logfile.endpointSecurity.warning(
                    "[Guardian] Main App still down. Forcing recovery for UID: \(userUID, privacy: .public)"
                )
                restarter(userUID)
            }
        }
    }
}
