//
//  ESManager+Watchdog.swift
//  ESExtension
//
//  Created by Doe Phương on 4/11/26.
//

import Darwin
import Foundation
import os

// MARK: - 75s Fail-Closed Watchdog & Main App Disconnect Recovery

extension ESManager {
    struct ExpiredPendingApp {
        let pid: pid_t
        let token: audit_token_t
        let name: String
        let path: String
    }

    func startPendingProcessesWatchdog() {
        Task.detached(priority: .utility) { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { break }
                self.purgeExpiredPendingProcesses(timeoutSeconds: 75)
            }
        }
    }

    func purgeExpiredPendingProcesses(timeoutSeconds: Double) {
        let now = ContinuousClock.now

        let expiredEntries: [ExpiredPendingApp] = pendingPIDLock.withLock {
            var expired: [ExpiredPendingApp] = []
            for (pid, entry) in self.pendingVerificationProcesses
                where now - entry.registeredAt > .seconds(timeoutSeconds) {
                expired.append(ExpiredPendingApp(
                    pid: pid,
                    token: entry.token,
                    name: entry.notification.name,
                    path: entry.notification.path
                ))
            }
            for entry in expired {
                self.pendingVerificationProcesses.removeValue(forKey: entry.pid)
            }
            return expired
        }

        for app in expiredEntries {
            terminateExpiredProcess(app, timeoutSeconds: timeoutSeconds)
        }
    }

    private func terminateExpiredProcess(_ app: ExpiredPendingApp, timeoutSeconds: Double) {
        let pid = app.pid
        guard let currentToken = auditToken(for: pid) else {
            Logfile.endpointSecurity.warning(
                "[Watchdog] Pending PID \(pid, privacy: .public) expired but process is already dead, skipping."
            )
            notifyAppAboutExpiredProcess(pid: pid)
            return
        }

        let expectedVersion = audit_token_to_pidversion(app.token)
        let currentVersion = audit_token_to_pidversion(currentToken)
        guard expectedVersion == currentVersion else {
            Logfile.endpointSecurity.fault(
                """
                [Watchdog] PID RECYCLING DETECTED for PID \(pid, privacy: .public)! \
                Expected version: \(expectedVersion, privacy: .public), \
                Current: \(currentVersion, privacy: .public). Aborting SIGKILL.
                """
            )
            notifyAppAboutExpiredProcess(pid: pid)
            return
        }

        Logfile.endpointSecurity.warning(
            """
            [Watchdog] Pending PID \(pid, privacy: .public) timed out after \(timeoutSeconds, privacy: .public)s. \
            Issuing SIGKILL.
            """
        )
        // Fail-Closed: SIGKILL to terminate unauthorized app, then SIGCONT to clean up kernel dispatch loop
        _ = kill(pid, SIGKILL)
        _ = kill(pid, SIGCONT)

        Logfile.endpointSecurity.notice(
            """
            [SecurityEvent:Rejected] App: \(app.name, privacy: .public) \
            (PID \(pid, privacy: .public)) | Path: \(app.path, privacy: .public) \
            | Reason: \(AuthDecisionReason.timeout.rawValue, privacy: .public)
            """
        )

        notifyAppAboutExpiredProcess(pid: pid)
    }

    private func notifyAppAboutExpiredProcess(pid: pid_t) {
        guard pid > 0 else { return }
        if let conn = pickAppConnection(),
           let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
               Logfile.esXPC.error("[Watchdog] XPC notifyProcessExited error: \(String(describing: error))")
           }) as? ESXPCProtocol {
            proxy.notifyProcessExited(pid: Int32(pid))
            Logfile.esXPC.debug("[Watchdog] Notified app about expired PID: \(pid, privacy: .public)")
        }
    }

    // MARK: - Fail-Closed Recovery on Main App Disconnect

    func handleMainAppDisconnect() {
        let hasPending = pendingPIDLock.withLock { () -> Bool in
            guard !self.pendingVerificationProcesses.isEmpty else { return false }
            // Gia hạn lại timer để Watchdog không kill khi AppLocker đang khởi động lại
            let now = ContinuousClock.now
            for pid in self.pendingVerificationProcesses.keys {
                self.pendingVerificationProcesses[pid]?.registeredAt = now
            }
            return true
        }

        if hasPending {
            let userUID = stateLock.withLock { activeUserUID } ?? getuid()
            Logfile.endpointSecurity.warning(
                """
                [ESManager] AppLocker disconnected with pending processes! \
                Preserving Fail-Closed queue & kickstarting agent for UID: \(userUID, privacy: .public)...
                """
            )
            stateLock.withLock { self.lastKickstartedUID = userUID }
            if !isTesting {
                AppLauncherUtils.forceEnableAndRestartAgent(for: userUID)
            }
        }
    }

    func reNotifyPendingVerificationProcesses(to conn: NSXPCConnection, uid: uid_t) {
        let pendingRecords = pendingPIDLock.withLock { () -> [BlockedNotification] in
            self.pendingVerificationProcesses.values
                .filter { $0.notification.uid == uid }
                .map { $0.notification }
        }
        guard !pendingRecords.isEmpty else { return }

        Logfile.esXPC.notice(
            """
            [ESConnections] AppLocker reconnected. Resending \(pendingRecords.count, privacy: .public) \
            pending processes for UID \(uid, privacy: .public)...
            """
        )
        for item in pendingRecords {
            self.performNotifyBlockRequest(
                conn: conn,
                name: item.name,
                path: item.path,
                cdhash: item.cdhash,
                targetPid: item.targetPid
            )
        }
    }
}
