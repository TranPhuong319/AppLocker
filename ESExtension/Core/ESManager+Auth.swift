//
//  ESManager+Auth.swift
//  ESExtension
//
//  Created by Doe Phương on 9/1/26.
//

import Foundation
import os

extension ESManager: ESAppProtocol {

    // Existing protocol methods are implemented in other files (TempAllowSHAStore, BlockedAppsStore, etc.)
    // But since they are extensions on ESManager, ESManager conforms.
    // However, Swift requires the conformation to be explicit or via extension.
    // If ESManager is already conforming in another file, this is fine.
    // We just implement the new method here.

    public func authenticate(
        clientNonce: Data,
        clientSig: Data,
        clientPublicKey: Data,
        withReply reply: @escaping (Data?, Data?, Data?, Bool) -> Void
    ) {
        guard let conn = NSXPCConnection.current() else {
            Logfile.es.error("Auth: No current XPC connection")
            reply(nil, nil, nil, false)
            return
        }

        Logfile.es.log("Auth: Received authentication request from pid=\(conn.processIdentifier)")

        // 1. Verify Client Signature using PROVIDED Public Key
        // We import the key data into a SecKey first
        guard let clientKey = KeychainHelper.shared.createPublicKey(from: clientPublicKey) else {
            Logfile.es.error("Auth: Failed to import client public key.")
            reply(nil, nil, nil, false)
            return
        }

        // Use verify(..., publicKey: SecKey)
        if !KeychainHelper.shared.verify(
            signature: clientSig, originalData: clientNonce, publicKey: clientKey
        ) {
            Logfile.es.error("Auth: Client signature verification failed using provided key!")
            reply(nil, nil, nil, false)
            return
        }

        Logfile.es.log("Auth: Client signature verified successfully.")

        // 2. Generate Server Nonce & Sign
        let serverNonce = Data.random(count: 32)
        let combinedData = clientNonce + serverNonce

        // Use our private key "es.extension.public" (private part) to sign
        let serverTag = KeychainHelper.Keys.extensionPublic

        // Ensure we have keys (should be generated at startup or on demand, but let's try)
        // If missing, we might need to generate them, but ideally Main should trigger generation or we do it lazily.
        if !KeychainHelper.shared.hasKey(tag: serverTag) {
            Logfile.es.log("Auth: Server keys missing, generating new pair...")
            try? KeychainHelper.shared.generateKeys(tag: serverTag)
        }

        guard let serverSig = KeychainHelper.shared.sign(data: combinedData, tag: serverTag) else {
            Logfile.es.error("Auth: Failed to sign server response.")
            reply(nil, nil, nil, false)
            return
        }

        // 2b. Export Server Public Key
        guard let serverPubKeyData = KeychainHelper.shared.exportPublicKey(tag: serverTag) else {
            Logfile.es.error("Auth: Failed to export server public key.")
            reply(nil, nil, nil, false)
            return
        }

        // 3. Mark as Authenticated
        xpcLock.perform {
            authenticatedConnections.insert(ObjectIdentifier(conn))
        }

        Logfile.es.log("Auth: Connection authenticated and authorized.")
        reply(serverNonce, serverSig, serverPubKeyData, true)
    }
}

// Extension for Data random
extension Data {
    static func random(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        return data
    }
}
