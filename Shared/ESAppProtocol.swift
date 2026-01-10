//
//  ESAppProtocol.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation

@objc public protocol ESAppProtocol {
    func allowSHAOnce(_ sha: String, withReply reply: @escaping (Bool) -> Void)

    func updateBlockedApps(_ apps: NSArray)

    func allowConfigAccess(_ pid: Int32, withReply reply: @escaping (Bool) -> Void)

    func updateLanguage(to code: String)

    // Reply: (ServerNonce?, ServerSignature?, Success)
    func authenticate(
        clientNonce: Data,
        clientSig: Data,
        clientPublicKey: Data,
        withReply reply: @escaping (Data?, Data?, Data?, Bool) -> Void
    )
}
