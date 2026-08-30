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

    func markPendingVerification(pid: pid_t) {
        pendingPIDLock.withLock {
            _ = pendingVerificationPIDs.insert(pid)
        }
    }

    func isPendingVerification(pid: pid_t) -> Bool {
        return pendingPIDLock.withLock {
            pendingVerificationPIDs.contains(pid)
        }
    }

    func removePendingVerification(pid: pid_t) {
        _ = pendingPIDLock.withLock {
            pendingVerificationPIDs.remove(pid)
        }
    }

    // MARK: - Batch Execution (SIGCONT / SIGKILL)

    func processPendingBatch(approved: [Int32], rejected: [Int32]) -> Bool {
        let approvedCount = processApprovedPIDs(approved)
        let rejectedCount = processRejectedPIDs(rejected)
        let processedCount = approvedCount + rejectedCount

        return processedCount > 0 || (approved.isEmpty && rejected.isEmpty)
    }

    private func processApprovedPIDs(_ approved: [Int32]) -> Int {
        var processedCount = 0
        for rawPID in approved {
            let pid = pid_t(rawPID)
            // ponytail: Safety guard: never pass pid <= 0 to kill() to prevent process group signals
            guard pid > 0 else { continue }

            let wasPending = pendingPIDLock.withLock {
                pendingVerificationPIDs.remove(pid) != nil
            }

            if wasPending {
                // Send SIGCONT to resume the suspended application
                let res = kill(pid, SIGCONT)
                if res == 0 {
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
        }
        return processedCount
    }

    private func processRejectedPIDs(_ rejected: [Int32]) -> Int {
        var processedCount = 0
        for rawPID in rejected {
            let pid = pid_t(rawPID)
            // ponytail: Safety guard: never pass pid <= 0 to kill() to prevent process group signals
            guard pid > 0 else { continue }

            let wasPending = pendingPIDLock.withLock {
                pendingVerificationPIDs.remove(pid) != nil
            }

            if wasPending {
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
        }
        return processedCount
    }
}
