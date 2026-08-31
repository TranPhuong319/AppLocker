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
        removePendingVerification(pid: exitingPID)

        // 1. Check if it's our main app
        guard isMainAppProcess(process) else {
            return
        }

        let pid = audit_token_to_pid(process.pointee.audit_token)
        Logfile.endpointSecurity.info("[Guardian] Main App (PID: \(pid, privacy: .public)) exited.")

        // 2. Check if shutdown was authorized
        let isAuthorized = stateLock.withLock { isShutdownAuthorized }

        if isAuthorized {
            Logfile.endpointSecurity.info("[Guardian] Shutdown was authorized. Watchdog standing down.")
            return
        }

        // 3. Unauthorized exit detected -> Self-Healing with 10s delay
        Logfile.endpointSecurity.warning("[Guardian] Unauthorized exit detected! Launching watchdog (10s delay)...")

        let uid = stateLock.withLock { activeUserUID }
        guard let userUID = uid else {
            Logfile.endpointSecurity.error("[Guardian] No active User UID found. Cannot kickstart.")
            return
        }

        // Schedule kickstart after 10 seconds via Swift Concurrency Task
        Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self else { return }
            Logfile.endpointSecurity.debug("[Guardian] Watchdog checking if Main App has recovered...")

            // Thread-safe atomic check via processIDLock
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
