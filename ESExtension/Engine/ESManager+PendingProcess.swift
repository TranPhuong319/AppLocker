//
//  ESManager+PendingProcess.swift
//  ESExtension
//
//  Created by Doe Phương on 31/7/26.
//

import Darwin
import Foundation
import os

extension ESManager {
    // MARK: - Pending Verification PID & Path Management

    func markPendingVerification(pid: pid_t, token: audit_token_t, notification: BlockedNotification) {
        pendingPIDLock.withLock {
            pendingVerificationProcesses[pid] = PendingProcessRecord(
                token: token,
                notification: notification,
                registeredAt: ContinuousClock.now
            )
        }
    }

    func isPendingVerification(pid: pid_t) -> Bool {
        return pendingPIDLock.withLock {
            pendingVerificationProcesses[pid] != nil
        }
    }

    @discardableResult
    func removePendingVerification(pid: pid_t) -> Bool {
        return pendingPIDLock.withLock {
            pendingVerificationProcesses.removeValue(forKey: pid) != nil
        }
    }

    func auditToken(for pid: pid_t) -> audit_token_t? {
        var token = audit_token_t()
        var size = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size)
        var task: mach_port_name_t = 0
        let kernReturn = task_name_for_pid(mach_task_self_, pid, &task)
        guard kernReturn == KERN_SUCCESS else { return nil }
        defer { mach_port_deallocate(mach_task_self_, task) }

        let infoRes = withUnsafeMutablePointer(to: &token) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                task_info(task, task_flavor_t(TASK_AUDIT_TOKEN), intPtr, &size)
            }
        }
        guard infoRes == KERN_SUCCESS else { return nil }
        return token
    }

    // MARK: - Watchdog Safety Valve (Fail-Closed)

    func startPendingProcessesWatchdog() {
        Task.detached(priority: .utility) { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { break }
                self.purgeExpiredPendingProcesses(timeoutSeconds: 75)
            }
        }
    }

    struct ValidatedPendingApp {
        let pid: pid_t
        let name: String
        let path: String
    }

    struct ExpiredPendingApp {
        let pid: pid_t
        let token: audit_token_t
        let name: String
        let path: String
    }

    private func purgeExpiredPendingProcesses(timeoutSeconds: Double) {
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
            (PID \(pid, privacy: .public)) | Path: \(app.path, privacy: .public) | Reason: Timeout
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

    // MARK: - Batch Execution (SIGCONT / SIGKILL)

    func processPendingBatch(approved: [Int32], rejected: [Int32], rejectionReason: String = "UserCancel") -> Bool {
        let approvedCount = processApprovedPIDs(approved)
        let rejectedCount = processRejectedPIDs(rejected, reason: rejectionReason)
        let processedCount = approvedCount + rejectedCount

        return processedCount > 0 || (approved.isEmpty && rejected.isEmpty)
    }

    private func validateAndConsumePendingPID(
        _ rawPID: Int32,
        actionName: String
    ) -> ValidatedPendingApp? {
        let pid = pid_t(rawPID)
        guard pid > 0 else { return nil }

        let savedEntry = pendingPIDLock.withLock {
            pendingVerificationProcesses.removeValue(forKey: pid)
        }

        guard let entry = savedEntry else { return nil }
        let expectedToken = entry.token

        // Process liveness & PID recycling defense via Mach audit token
        guard let currentToken = auditToken(for: pid) else {
            Logfile.endpointSecurity.warning(
                "[PendingProcess] \(actionName, privacy: .public) PID \(pid, privacy: .public) is dead, skipping."
            )
            return nil
        }

        let expectedVersion = audit_token_to_pidversion(expectedToken)
        let currentVersion = audit_token_to_pidversion(currentToken)
        guard expectedVersion == currentVersion else {
            Logfile.endpointSecurity.fault(
                """
                [PendingProcess] PID RECYCLING DETECTED for PID \(pid, privacy: .public)! \
                Expected version: \(expectedVersion, privacy: .public), \
                Current: \(currentVersion, privacy: .public). Aborting \(actionName, privacy: .public).
                """
            )
            return nil
        }

        return ValidatedPendingApp(pid: pid, name: entry.notification.name, path: entry.notification.path)
    }

    private func processApprovedPIDs(_ approved: [Int32]) -> Int {
        var processedCount = 0
        for rawPID in approved {
            guard let item = validateAndConsumePendingPID(rawPID, actionName: "Approved") else {
                continue
            }
            let pid = item.pid

            let result = kill(pid, SIGCONT)
            if result == 0 {
                Logfile.endpointSecurity.notice(
                    """
                    [SecurityEvent:Approved] App: \(item.name, privacy: .public) \
                    (PID \(pid, privacy: .public)) | Path: \(item.path, privacy: .public)
                    """
                )
            } else {
                Logfile.endpointSecurity.error(
                    """
                    [PendingProcess] Failed to send SIGCONT to PID \(pid, privacy: .public): \
                    errno \(errno, privacy: .public)
                    """
                )
            }
            processedCount += 1
        }
        return processedCount
    }

    private func processRejectedPIDs(_ rejected: [Int32], reason: String) -> Int {
        var processedCount = 0
        for rawPID in rejected {
            guard let item = validateAndConsumePendingPID(rawPID, actionName: "Rejected") else {
                continue
            }
            let pid = item.pid

            // Send SIGKILL followed by SIGCONT to unfreeze XNU kernel dispatch loop
            // and terminate cleanly without hanging launchd
            let killRes = kill(pid, SIGKILL)
            _ = kill(pid, SIGCONT)
            if killRes == 0 {
                Logfile.endpointSecurity.notice(
                    """
                    [SecurityEvent:Rejected] App: \(item.name, privacy: .public) \
                    (PID \(pid, privacy: .public)) | Path: \(item.path, privacy: .public) \
                    | Reason: \(reason, privacy: .public)
                    """
                )
            } else {
                Logfile.endpointSecurity.error(
                    """
                    [PendingProcess] Failed to send SIGKILL to PID \(pid, privacy: .public): \
                    errno \(errno, privacy: .public)
                    """
                )
            }
            processedCount += 1
        }
        return processedCount
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
            AppLauncherUtils.forceEnableAndRestartAgent(for: userUID)
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
