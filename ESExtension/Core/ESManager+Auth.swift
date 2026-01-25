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
        // 0. Wait for Async KeyGen (Start-up race protection)
        // If keys are generating (<100ms), this will block this specific request briefly.
        _ = keyGenGroup.wait(timeout: .now() + 5) // 5s timeout safety
        
        guard let conn = NSXPCConnection.current() else {
            Logfile.es.error("Auth: No current XPC connection")
            reply(nil, nil, nil, false)
            return
        }

        Logfile.es.log("Auth: Received authentication request from pid=\(conn.processIdentifier)")

        // 1. Verify Client Signature (Fast - no I/O)
        if !KeychainHelper.shared.verify(
            signature: clientSig, originalData: clientNonce, publicKeyData: clientPublicKey
        ) {
            Logfile.es.error("Auth: Client signature verification failed!")
            reply(nil, nil, nil, false)
            return
        }

        let serverTag = KeychainHelper.Keys.extensionPublic

        // 2. Check if keys exist WITHOUT blocking
        let needsKeyGen = !KeychainHelper.shared.hasKey(tag: serverTag)

        if needsKeyGen {
            // ⚠️ CRITICAL: Generate keys OFF XPC thread to avoid blocking
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    Logfile.es.error("Auth: ESManager deallocated during async key gen")
                    reply(nil, nil, nil, false)
                    return
                }

                // Use atomic flag to ensure single generation
                var shouldGenerate = false
                self.xpcConnectionLock.perform {
                    if !KeychainHelper.shared.hasKey(tag: serverTag) {
                        shouldGenerate = true
                    }
                }

                if shouldGenerate {
                    Logfile.es.log("Auth: Generating server keys (async)...")
                    do {
                        try KeychainHelper.shared.generateKeys(tag: serverTag)
                    } catch {
                        Logfile.es.error("Auth: Key generation failed: \(error)")
                        reply(nil, nil, nil, false)
                        return
                    }
                }

                // Continue authentication after key gen - this method MUST call reply
                self.completeAuthentication(
                    conn: conn,
                    clientNonce: clientNonce,
                    serverTag: serverTag,
                    reply: reply
                )
            }
        } else {
            // Keys exist - authenticate immediately
            completeAuthentication(
                conn: conn,
                clientNonce: clientNonce,
                serverTag: serverTag,
                reply: reply
            )
        }
    }

    private func completeAuthentication(
        conn: NSXPCConnection,
        clientNonce: Data,
        serverTag: String,
        reply: @escaping (Data?, Data?, Data?, Bool) -> Void
    ) {
        let serverNonce = Data.random(count: 32)
        let combinedData = clientNonce + serverNonce

        guard let serverSig = KeychainHelper.shared.sign(data: combinedData, tag: serverTag) else {
            Logfile.es.error("Auth: Failed to sign server response.")
            reply(nil, nil, nil, false)
            return
        }

        guard let serverPubKeyData = KeychainHelper.shared.exportPublicKey(tag: serverTag) else {
            Logfile.es.error("Auth: Failed to export server public key.")
            reply(nil, nil, nil, false)
            return
        }

        // 3. Mark as Authenticated & Cache PID
        xpcConnectionLock.perform {
            authenticatedConnections.insert(ObjectIdentifier(conn))
        }

        cacheMainAppPID(from: conn)

        Logfile.es.log("Auth: Connection authenticated.")
        reply(serverNonce, serverSig, serverPubKeyData, true)
    }
}

extension Data {
    static func random(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        return data
    }
}
