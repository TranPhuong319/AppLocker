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

    struct ValidatedPendingApp {
        let pid: pid_t
        let name: String
        let path: String
    }

    // MARK: - Batch Execution (SIGCONT / SIGKILL)

    func processPendingBatch(
        approved: [Int32],
        rejected: [Int32],
        rejectionReason: String = AuthDecisionReason.userCancel.rawValue
    ) -> Bool {
        let approvedCount = processApprovedPIDs(approved)
        let rejectedCount = processRejectedPIDs(rejected, reason: rejectionReason)
        let processedCount = approvedCount + rejectedCount

        return processedCount > 0 || (approved.isEmpty && rejected.isEmpty)
    }

    enum ProcessIdentityValidation {
        case valid
        case dead
        case recycled(expected: Int32, current: Int32)
    }

    func verifyProcessIdentity(pid: pid_t, expectedToken: audit_token_t) -> ProcessIdentityValidation {
        guard pid > 0, kill(pid, 0) == 0, let currentToken = Self.auditToken(for: pid) else {
            return .dead
        }
        let expectedVersion = audit_token_to_pidversion(expectedToken)
        let currentVersion = audit_token_to_pidversion(currentToken)
        guard expectedVersion == currentVersion else {
            return .recycled(expected: expectedVersion, current: currentVersion)
        }
        return .valid
    }

    @discardableResult
    func terminateFrozenProcess(pid: pid_t) -> Int32 {
        guard pid > 0 else { return -1 }
        // Send SIGKILL followed by SIGCONT to unfreeze XNU kernel dispatch loop
        // and terminate cleanly without hanging launchd
        let killRes = kill(pid, SIGKILL)
        _ = kill(pid, SIGCONT)
        return killRes
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

        switch verifyProcessIdentity(pid: pid, expectedToken: entry.token) {
        case .dead:
            Logfile.endpointSecurity.warning(
                "[PendingProcess] \(actionName, privacy: .public) PID \(pid, privacy: .public) is dead, skipping."
            )
            return nil
        case .recycled(let expectedVersion, let currentVersion):
            Logfile.endpointSecurity.fault(
                """
                [PendingProcess] PID RECYCLING DETECTED for PID \(pid, privacy: .public)! \
                Expected version: \(expectedVersion, privacy: .public), \
                Current: \(currentVersion, privacy: .public). Aborting \(actionName, privacy: .public).
                """
            )
            return nil
        case .valid:
            return ValidatedPendingApp(pid: pid, name: entry.notification.name, path: entry.notification.path)
        }
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
            let killRes = terminateFrozenProcess(pid: pid)
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
}
