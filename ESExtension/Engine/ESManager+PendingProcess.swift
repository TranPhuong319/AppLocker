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
        pendingPIDLock.perform {
            _ = pendingVerificationPIDs.insert(pid)
        }
    }

    func isPendingVerification(pid: pid_t) -> Bool {
        return pendingPIDLock.sync {
            pendingVerificationPIDs.contains(pid)
        }
    }

    func removePendingVerification(pid: pid_t) {
        pendingPIDLock.perform {
            pendingVerificationPIDs.remove(pid)
        }
    }

    // MARK: - Batch Execution (SIGCONT / SIGKILL)

    func processPendingBatch(approved: [Int32], rejected: [Int32]) -> Bool {
        var processedCount = 0

        // Process Approved PIDs (SIGCONT)
        for rawPID in approved {
            let pid = pid_t(rawPID)
            // ponytail: Safety guard: never pass pid <= 0 to kill() to prevent process group signals
            guard pid > 0 else { continue }

            let wasPending = pendingPIDLock.sync {
                pendingVerificationPIDs.remove(pid) != nil
            }

            if wasPending {
                // Send SIGCONT to resume the suspended application
                let res = kill(pid, SIGCONT)
                if res == 0 {
                    Logfile.endpointSecurity.log("Successfully sent SIGCONT to approved PID \(pid)")
                } else {
                    Logfile.endpointSecurity.error("Failed to send SIGCONT to PID \(pid): errno \(errno)")
                }
                processedCount += 1
            }
        }

        // Process Rejected PIDs (SIGKILL)
        for rawPID in rejected {
            let pid = pid_t(rawPID)
            // ponytail: Safety guard: never pass pid <= 0 to kill() to prevent process group signals
            guard pid > 0 else { continue }

            let wasPending = pendingPIDLock.sync {
                pendingVerificationPIDs.remove(pid) != nil
            }

            if wasPending {
                // Send SIGKILL to terminate the suspended application
                let res = kill(pid, SIGKILL)
                if res == 0 {
                    Logfile.endpointSecurity.log("Successfully sent SIGKILL to rejected PID \(pid)")
                } else {
                    Logfile.endpointSecurity.error("Failed to send SIGKILL to PID \(pid): errno \(errno)")
                }
                processedCount += 1
            }
        }

        return processedCount > 0 || (approved.isEmpty && rejected.isEmpty)
    }
}
