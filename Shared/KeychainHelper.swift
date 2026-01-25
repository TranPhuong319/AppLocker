//
//  KeychainHelper.swift
//  Shared
//
//  Created by Doe Phương on 9/1/26.
//

import Foundation
import Security
import os

final class KeychainHelper {
    static let shared = KeychainHelper()

    // Identifiers
    struct Keys {
        static let appPublic = "com.TranPhuong319.AppLocker.public"
        static let appPrivate = "com.TranPhuong319.AppLocker.private"

        static let extensionPublic = "com.TranPhuong319.AppLocker.ESExtension.public"
        static let extensionPrivate = "com.TranPhuong319.AppLocker.ESExtension.private"

        static let helperPublic = "com.TranPhuong319.AppLocker.Helper.public"
        static let helperPrivate = "com.TranPhuong319.AppLocker.Helper.private"
    }

    // Ephemeral Cache (Memory only)
    // This fixes the 'Password Prompt after update' issue for Ad-hoc builds.
    private var keyCache: [String: Data] = [:]
    private let cacheLock = NSLock()

    private init() {
        // No longer need Keychain initialization for ephemeral keys
    }

    // MARK: - Key Generation

    /// Generates EC P-256 keys and stores them in memory cache
    func generateKeys(tag: String) throws {
        // 1. Generate SecKey Pair (EC P-256)
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false  // DO NOT save to Keychain
        ]

        var keyError: Unmanaged<CFError>?
        guard let privateSecKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &keyError) else {
            throw keyError!.takeRetainedValue() as Error
        }

        guard let publicSecKey = SecKeyCopyPublicKey(privateSecKey) else {
            throw NSError(
                domain: "KeychainHelper", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to copy public key"])
        }

        // 2. Export to Data
        guard let privateKeyData = SecKeyCopyExternalRepresentation(privateSecKey, &keyError) as Data?,
            let publicKeyData = SecKeyCopyExternalRepresentation(publicSecKey, &keyError) as Data?
        else {
            throw keyError!.takeRetainedValue() as Error
        }

        // 3. Store in Memory Cache
        let privateKeyTag = derivePrivateTag(from: tag)

        cacheLock.lock()
        keyCache[privateKeyTag] = privateKeyData
        keyCache[tag] = publicKeyData
        cacheLock.unlock()

        Logfile.keychain.pLog("KeychainHelper: Generated and cached ephemeral EC keys for \(tag)")
    }

    // MARK: - Sign & Verify

    func sign(data: Data, tag: String) -> Data? {
        let privateKeyTag = derivePrivateTag(from: tag)

        // 1. Retrieve Private Key Data from Cache
        cacheLock.lock()
        let privateKeyData = keyCache[privateKeyTag]
        cacheLock.unlock()

        guard let pData = privateKeyData else {
            Logfile.keychain.pError(
                "KeychainHelper: Private key not found in cache for: \(privateKeyTag)")
            return nil
        }

        // 2. Create SecKey from Data
        guard let privateSecKey = createKey(from: pData, isPrivate: true) else { return nil }

        // 3. Sign using ECDSA SHA256
        var keyError: Unmanaged<CFError>?
        guard
            let signature = SecKeyCreateSignature(
                privateSecKey,
                .ecdsaSignatureMessageX962SHA256,
                data as CFData,
                &keyError
            ) as Data?
        else {
            Logfile.keychain.error(
                "KeychainHelper: Signing failed: \(keyError!.takeRetainedValue() as Error)")
            return nil
        }

        return signature
    }

    func verify(signature: Data, originalData: Data, publicKeyData: Data) -> Bool {
        guard let publicKey = createKey(from: publicKeyData, isPrivate: false) else { return false }
        return verify(signature: signature, originalData: originalData, publicKey: publicKey)
    }

    func verify(signature: Data, originalData: Data, pubKeyTag: String) -> Bool {
        cacheLock.lock()
        let publicKeyData = keyCache[pubKeyTag]
        cacheLock.unlock()

        guard let data = publicKeyData else {
            Logfile.keychain.pError("KeychainHelper: Public key not found in cache: \(pubKeyTag)")
            return false
        }
        return verify(signature: signature, originalData: originalData, publicKeyData: data)
    }

    func verify(signature: Data, originalData: Data, publicKey: SecKey) -> Bool {
        var keyError: Unmanaged<CFError>?
        let result = SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            originalData as CFData,
            signature as CFData,
            &keyError
        )
        if let keyError = keyError {
            Logfile.keychain.error(
                "KeychainHelper: Verify error: \(keyError.takeRetainedValue() as Error)")
        }
        return result
    }

    // MARK: - Exports & Utils

    func exportPublicKey(tag: String) -> Data? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return keyCache[tag]
    }

    func hasKey(tag: String) -> Bool {
        let privateTag = derivePrivateTag(from: tag)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return keyCache[privateTag] != nil
    }

    // Internal helper to hydrate SecKey from Data
    private func createKey(from data: Data, isPrivate: Bool) -> SecKey? {
        let keyClass = isPrivate ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic
        let options: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: keyClass,
            kSecAttrKeySizeInBits as String: 256
        ]

        var keyError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, options as CFDictionary, &keyError) else {
            Logfile.keychain.error(
                "KeychainHelper: Failed to create key from data (private=\(isPrivate)): \(keyError!.takeRetainedValue() as Error)"
            )
            return nil
        }
        return key
    }

    func createPublicKey(from data: Data) -> SecKey? {
        return createKey(from: data, isPrivate: false)
    }

    private func derivePrivateTag(from publicTag: String) -> String {
        if publicTag == Keys.appPublic { return Keys.appPrivate }
        if publicTag == Keys.extensionPublic { return Keys.extensionPrivate }
        if publicTag == Keys.helperPublic { return Keys.helperPrivate }
        return publicTag + ".private"
    }
}
