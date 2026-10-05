//
//  ESEventNotifyExit.swift
//  ESExtension
//
//  Created by Doe Phương on 7/2/26.
//

import EndpointSecurity
import Foundation
import os

extension ESManager {
    func handleNotifyExit(client: OpaquePointer, message: ESMessage) {
        let process = message.pointee.process
        let exitingPID = audit_token_to_pid(process.pointee.audit_token)
        let exitingUID = audit_token_to_euid(process.pointee.audit_token)

        notifyPendingProcessExitIfNeeded(pid: exitingPID, uid: exitingUID)

        guard isMainAppProcess(process) else { return }
        handleMainAppExit(process: process, exitStat: message.pointee.event.exit.stat)
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

    private func handleMainAppExit(process: UnsafePointer<es_process_t>, exitStat: Int32) {
        let pid = audit_token_to_pid(process.pointee.audit_token)
        processIDLock.withLock {
            if self.lastKnownMainAppPID == pid {
                self.lastKnownMainAppPID = nil
            }
        }
        Logfile.endpointSecurity.info("[Guardian] Main App (PID: \(pid, privacy: .public)) exited.")

        let isAuthorized = stateLock.withLock { isShutdownAuthorized }
        if isAuthorized || exitStat == 0 {
            Logfile.endpointSecurity.info(
                """
                [Guardian] Shutdown was clean/authorized (stat: \(exitStat, privacy: .public), \
                auth: \(isAuthorized, privacy: .public)). Watchdog standing down.
                """
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

        Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self else { return }
            Logfile.endpointSecurity.debug("[Guardian] Watchdog checking if Main App has recovered...")

            let isAppRunning = self.processIDLock.withLock { self.authenticatedMainAppPID != nil }
            if isAppRunning {
                Logfile.endpointSecurity.info("[Guardian] Main App recovered via launchd. Watchdog cancelled.")
            } else {
                Logfile.endpointSecurity.warning(
                    "[Guardian] Main App still down. Forcing recovery for UID: \(userUID, privacy: .public)"
                )
                AppLauncherUtils.forceEnableAndRestartAgent(for: userUID)
            }
        }
    }
}
