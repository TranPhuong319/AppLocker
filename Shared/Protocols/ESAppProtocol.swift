//
//  ESAppProtocol.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation

public enum AuthDecisionReason: String, Sendable {
    case userApprove = "UserApprove"
    case userCancel = "UserCancel"
    case timeout = "Timeout"
}

@objc public protocol ESAppProtocol {
    func allowConfigAccess(_ processID: Int32, withReply reply: @escaping (Bool) -> Void)

    func updateLanguage(to code: String)

    func processPendingApps(
        approvedPIDs: [Int32],
        rejectedPIDs: [Int32],
        rejectionReason: String,
        withReply reply: @escaping (Bool) -> Void
    )

    func authorizeShutdown(_ authorized: Bool, withReply reply: @escaping (Bool) -> Void)

    func updateIncomingCallRingingState(_ isRinging: Bool)
    func refreshPendingWatchdog(pids: [Int32])
}
