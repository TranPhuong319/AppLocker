//
//  ESManager+Auth.swift
//  ESExtension
//
//  Created by Doe Phương on 9/1/26.
//

import Foundation
import os

extension ESManager: ESAppProtocol {

    public func processPendingApps(
        approvedPIDs: [Int32],
        rejectedPIDs: [Int32],
        rejectionReason: String,
        withReply reply: @escaping (Bool) -> Void
    ) {
        guard isCurrentConnectionAuthenticated() else {
            Logfile.esSecurity.error("[Auth] processPendingApps rejected: Connection not authenticated")
            reply(false)
            return
        }

        Logfile.esSecurity.debug(
            """
            [Auth] processPendingApps: Approved PIDs \(approvedPIDs, privacy: .public), \
            Rejected PIDs \(rejectedPIDs, privacy: .public), Reason: \(rejectionReason, privacy: .public)
            """
        )
        let result = processPendingBatch(
            approved: approvedPIDs,
            rejected: rejectedPIDs,
            rejectionReason: rejectionReason
        )
        reply(result)
    }

    public func updateIncomingCallRingingState(_ isRinging: Bool) {
        guard isCurrentConnectionAuthenticated() else {
            Logfile.esSecurity.error("[Auth] updateIncomingCallRingingState rejected: Connection not authenticated")
            return
        }

        stateLock.withLock {
            self.isIncomingCallActive = isRinging
        }
        Logfile.esSecurity.notice(
            "[Auth] Incoming call ringing state updated to: \(isRinging, privacy: .public)"
        )
    }

    public func refreshPendingWatchdog(pids: [Int32]) {
        guard isCurrentConnectionAuthenticated() else {
            Logfile.esSecurity.error("[Watchdog] refreshPendingWatchdog rejected: Connection not authenticated")
            return
        }

        let now = ContinuousClock.now
        pendingPIDLock.withLock {
            for rawPID in pids where rawPID > 0 {
                let pid = pid_t(rawPID)
                if var record = self.pendingVerificationProcesses[pid] {
                    record.registeredAt = now
                    self.pendingVerificationProcesses[pid] = record
                    Logfile.endpointSecurity.notice(
                        "[Watchdog] Reset 75s kernel watchdog timer for PID \(pid, privacy: .public)"
                    )
                }
            }
        }
    }
}
