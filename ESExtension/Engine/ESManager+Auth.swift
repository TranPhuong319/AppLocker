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
            Rejected PIDs \(rejectedPIDs, privacy: .public)
            """
        )
        let result = processPendingBatch(approved: approvedPIDs, rejected: rejectedPIDs)
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
}
