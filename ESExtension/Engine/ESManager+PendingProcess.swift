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

    func markPendingVerification(pid: pid_t, token: audit_token_t) {
        pendingPIDLock.withLock {
            pendingVerificationProcesses[pid] = token
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

    // MARK: - Batch Execution (SIGCONT / SIGKILL)

    func processPendingBatch(approved: [Int32], rejected: [Int32]) -> Bool {
        let approvedCount = processApprovedPIDs(approved)
        let rejectedCount = processRejectedPIDs(rejected)
        let processedCount = approvedCount + rejectedCount

        return processedCount > 0 || (approved.isEmpty && rejected.isEmpty)
    }

    private func validateAndConsumePendingPID(_ rawPID: Int32, actionName: String) -> pid_t? {
        let pid = pid_t(rawPID)
        // ponytail: Safety guard: verify PID > 0 and process is still alive before signaling
        guard pid > 0, kill(pid, 0) == 0 else {
            let removed = pendingPIDLock.withLock {
                pendingVerificationProcesses.removeValue(forKey: pid) != nil
            }
            if removed {
                Logfile.endpointSecurity.warning(
                    "[PendingProcess] \(actionName, privacy: .public) PID \(pid, privacy: .public) is dead, skipping."
                )
            }
            return nil
        }

        let savedToken = pendingPIDLock.withLock {
            pendingVerificationProcesses.removeValue(forKey: pid)
        }

        guard let expectedToken = savedToken else { return nil }

        if let currentToken = auditToken(for: pid) {
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
        }
        return pid
    }

    private func processApprovedPIDs(_ approved: [Int32]) -> Int {
        var processedCount = 0
        for rawPID in approved {
            guard let pid = validateAndConsumePendingPID(rawPID, actionName: "Approved") else {
                continue
            }

            let result = kill(pid, SIGCONT)
            if result == 0 {
                Logfile.endpointSecurity.debug(
                    "[PendingProcess] Successfully sent SIGCONT to approved PID \(pid, privacy: .public)"
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

    private func processRejectedPIDs(_ rejected: [Int32]) -> Int {
        var processedCount = 0
        for rawPID in rejected {
            guard let pid = validateAndConsumePendingPID(rawPID, actionName: "Rejected") else {
                continue
            }

            // Send SIGKILL followed by SIGCONT to unfreeze XNU kernel dispatch loop
            // and terminate cleanly without hanging launchd
            let killRes = kill(pid, SIGKILL)
            let contRes = kill(pid, SIGCONT)
            if killRes == 0 {
                Logfile.endpointSecurity.debug(
                    """
                    [PendingProcess] Successfully sent SIGKILL+SIGCONT to rejected \
                    PID \(pid, privacy: .public) (contRes=\(contRes, privacy: .public))
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
