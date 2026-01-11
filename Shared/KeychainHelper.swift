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

    /// Generates RSA keys and stores them in memory cache
    func generateKeys(tag: String) throws {
        // 1. Generate SecKey Pair
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecAttrIsPermanent as String: false  // DO NOT save to Keychain
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw NSError(
                domain: "KeychainHelper", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to copy public key"])
        }

        // 2. Export to Data
        guard let privateData = SecKeyCopyExternalRepresentation(privateKey, &error) as Data?,
            let publicData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
        else {
            throw error!.takeRetainedValue() as Error
        }

        // 3. Store in Memory Cache
        let privateTag = derivePrivateTag(from: tag)

        cacheLock.lock()
        keyCache[privateTag] = privateData
        keyCache[tag] = publicData
        cacheLock.unlock()

        Logfile.keychain.log("KeychainHelper: Generated and cached ephemeral keys for \(tag)")
    }

    // MARK: - Sign & Verify

    func sign(data: Data, tag: String) -> Data? {
        let privateTag = derivePrivateTag(from: tag)

        // 1. Retrieve Private Key Data from Cache
        cacheLock.lock()
        let privateData = keyCache[privateTag]
        cacheLock.unlock()

        guard let pData = privateData else {
            Logfile.keychain.error(
                "KeychainHelper: Private key not found in cache for: \(privateTag)")
            return nil
        }

        // 2. Create SecKey from Data
        guard let privateKey = createKey(from: pData, isPrivate: true) else { return nil }

        // 3. Sign
        var error: Unmanaged<CFError>?
        guard
            let signature = SecKeyCreateSignature(
                privateKey,
                .rsaSignatureMessagePKCS1v15SHA256,
                data as CFData,
                &error
            ) as Data?
        else {
            Logfile.keychain.error(
                "KeychainHelper: Signing failed: \(error!.takeRetainedValue() as Error)")
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
        let pubData = keyCache[pubKeyTag]
        cacheLock.unlock()

        guard let data = pubData else {
            Logfile.keychain.error("KeychainHelper: Public key not found in cache: \(pubKeyTag)")
            return false
        }
        return verify(signature: signature, originalData: originalData, publicKeyData: data)
    }

    func verify(signature: Data, originalData: Data, publicKey: SecKey) -> Bool {
        var error: Unmanaged<CFError>?
        let result = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            originalData as CFData,
            signature as CFData,
            &error
        )
        if let error = error {
            Logfile.keychain.error(
                "KeychainHelper: Verify error: \(error.takeRetainedValue() as Error)")
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
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: keyClass,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, options as CFDictionary, &error) else {
            Logfile.keychain.error(
                "KeychainHelper: Failed to create key from data (private=\(isPrivate)): \(error!.takeRetainedValue() as Error)"
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
