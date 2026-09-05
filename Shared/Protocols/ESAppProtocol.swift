//
//  ESAppProtocol.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation

@objc public protocol ESAppProtocol {
    func allowConfigAccess(_ processID: Int32, withReply reply: @escaping (Bool) -> Void)

    func updateLanguage(to code: String)

    func authenticate(
        clientNonce: Data,
        clientSig: Data,
        clientPublicKey: Data,
        withReply reply: @escaping (Data?, Data?, Data?, Bool) -> Void
    )

    func processPendingApps(
        approvedPIDs: [Int32],
        rejectedPIDs: [Int32],
        withReply reply: @escaping (Bool) -> Void
    )

    func authorizeShutdown(_ authorized: Bool, withReply reply: @escaping (Bool) -> Void)

    func updateIncomingCallRingingState(_ isRinging: Bool)
}
