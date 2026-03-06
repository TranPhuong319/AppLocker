//
//  AppLockerHelperProtocol.swift
//  AppLockerHelper
//
//  Created by Doe Phương on 04/08/2025.
//

import Foundation

@objc(AppLockerHelperProtocol)
public protocol AppLockerHelperProtocol {
    @objc func sendBatch(_ commands: [[String: Any]], withReply reply: @escaping (Bool, String) -> Void)

    @objc func uninstallHelper(withReply reply: @escaping (Bool, String) -> Void)

    @objc func authenticate(
        clientNonce: Data,
        clientSig: Data,
        clientPublicKey: Data,
        withReply reply: @escaping (Data?, Data?, Data?, Bool) -> Void
    )
}
