//
//  KeychainHelper.swift
//  Shared
//
//  Created by Doe Phương on 9/1/26.
//

import Foundation
import CryptoKit
import os

final class KeychainHelper: Sendable {
    static let shared = KeychainHelper()

    // Identifiers
    struct Keys {
        static let appPublic = "com.TranPhuong319.AppLocker.public"
        static let extensionPublic = "com.TranPhuong319.AppLocker.ESExtension.public"
    }

    private struct State {
        var privateKeys: [String: P256.Signing.PrivateKey] = [:]
        var publicKeys: [String: Data] = [:]
    }

    // Ephemeral Cache (Memory only) protected by native OSAllocatedUnfairLock
    private let state = OSAllocatedUnfairLock(initialState: State())

    private init() {}

    // MARK: - Key Generation

    /// Generates EC P-256 keys and stores them in memory cache
    func generateKeys(tag: String) throws {
        let privateKey = P256.Signing.PrivateKey()
        let publicKeyData = privateKey.publicKey.x963Representation

        state.withLock {
            $0.privateKeys[tag] = privateKey
            $0.publicKeys[tag] = publicKeyData
        }

        Logfile.security.debug("[Keychain] Generated and cached ephemeral EC keys for \(tag, privacy: .public)")
    }

    // MARK: - Sign & Verify

    func sign(data: Data, tag: String) -> Data? {
        let privateKey = state.withLock { $0.privateKeys[tag] }

        guard let key = privateKey else {
            Logfile.security.error("[Keychain] Private key not found in cache for: \(tag, privacy: .public)")
            return nil
        }

        do {
            let signature = try key.signature(for: data)
            return signature.derRepresentation
        } catch {
            Logfile.security.error(
                "[Keychain] Signing failed for tag \(tag, privacy: .public): \(error.localizedDescription)"
            )
            return nil
        }
    }

    func verify(signature: Data, originalData: Data, publicKeyData: Data) -> Bool {
        do {
            let pubKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
            let sig = try P256.Signing.ECDSASignature(derRepresentation: signature)
            return pubKey.isValidSignature(sig, for: originalData)
        } catch {
            Logfile.security.error("[Keychain] Signature verification error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Exports & Utils

    func exportPublicKey(tag: String) -> Data? {
        state.withLock { $0.publicKeys[tag] }
    }

    func hasKey(tag: String) -> Bool {
        state.withLock { $0.privateKeys[tag] != nil }
    }
}
