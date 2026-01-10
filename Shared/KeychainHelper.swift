//
//  KeychainHelper.swift
//  Shared
//
//  Created by Doe Phương on 9/1/26.
//

import Foundation
import Security
import KeychainAccess
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

    // KeychainAccess instance
    private let keychain: Keychain

    private init() {
        // Use the Bundle Identifier as the Service Name to isolate App and Extension keychain items.
        // This prevents the App (User) from conflicting with Extension (System/Root) items.
        let serviceName = Bundle.main.bundleIdentifier ?? "com.TranPhuong319.AppLocker.XPCAuth"
        self.keychain = Keychain(service: serviceName)
            .accessibility(.afterFirstUnlock)
    }

    // MARK: - Key Generation

    /// Generates RSA keys and stores them as Data in Keychain
    func generateKeys(tag: String) throws {
        // 1. Generate SecKey Pair
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw NSError(domain: "KeychainHelper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to copy public key"])
        }

        // 2. Export to Data
        guard let privateData = SecKeyCopyExternalRepresentation(privateKey, &error) as Data?,
              let publicData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw error!.takeRetainedValue() as Error
        }

        // 3. Store in Keychain (Private and Public)
        // We derive the private key tag from the public tag convention we defined
        // Keys.appPublic -> Keys.appPrivate
        let privateTag: String
        if tag == Keys.appPublic { privateTag = Keys.appPrivate } else if tag == Keys.extensionPublic { privateTag = Keys.extensionPrivate } else { privateTag = tag + ".private" }

        // Remove old if exists
        try? keychain.remove(privateTag)
        try? keychain.remove(tag)

        try keychain.set(privateData, key: privateTag)
        try keychain.set(publicData, key: tag)

        Logfile.keychain.log("KeychainHelper: Generated and stored keys for \(tag)")
    }

    // MARK: - Sign & Verify

    func sign(data: Data, tag: String) -> Data? {
        // Determine private key tag
        let privateTag: String
        if tag == Keys.appPublic { privateTag = Keys.appPrivate } else if tag == Keys.extensionPublic { privateTag = Keys.extensionPrivate } else { privateTag = tag + ".private" }

        // 1. Retrieve Private Key Data
        guard let privateData = try? keychain.getData(privateTag) else {
            Logfile.keychain.error("KeychainHelper: Private key not found for signing: \(privateTag)")
            return nil
        }

        // 2. Create SecKey from Data
        guard let privateKey = createKey(from: privateData, isPrivate: true) else { return nil }

        // 3. Sign
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) as Data? else {
            Logfile.keychain.error("KeychainHelper: Signing failed: \(error!.takeRetainedValue() as Error)")
            return nil
        }

        return signature
    }

    func verify(signature: Data, originalData: Data, publicKeyData: Data) -> Bool {
        guard let publicKey = createKey(from: publicKeyData, isPrivate: false) else { return false }
        return verify(signature: signature, originalData: originalData, publicKey: publicKey)
    }

    // Existing verify overload for compatibility if needed, but we prefer passing data directly
    func verify(signature: Data, originalData: Data, pubKeyTag: String) -> Bool {
        guard let pubData = try? keychain.getData(pubKeyTag) else {
             Logfile.keychain.error("KeychainHelper: Public key not found for verification: \(pubKeyTag)")
             return false
        }
        return verify(signature: signature, originalData: originalData, publicKeyData: pubData)
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
            Logfile.keychain.error("KeychainHelper: Verify error: \(error.takeRetainedValue() as Error)")
        }
        return result
    }

    // MARK: - Exports & Utils

    func exportPublicKey(tag: String) -> Data? {
        return try? keychain.getData(tag)
    }

    func hasKey(tag: String) -> Bool {
        // Check for private key mainly, as that's what we need to operate as this entity
        let privateTag: String
        if tag == Keys.appPublic { privateTag = Keys.appPrivate } else if tag == Keys.extensionPublic { privateTag = Keys.extensionPrivate } else { privateTag = tag + ".private" }

        return (try? keychain.getData(privateTag)) != nil
    }

    // Helper to hydrate SecKey from Data
    private func createKey(from data: Data, isPrivate: Bool) -> SecKey? {
        let keyClass = isPrivate ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic
        let options: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: keyClass,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, options as CFDictionary, &error) else {
            Logfile.keychain.error("KeychainHelper: Failed to create key from data (private=\(isPrivate)): \(error!.takeRetainedValue() as Error)")
            return nil
        }
        return key
    }

    // Helper for public key creation from raw data (wrapper for above)
    func createPublicKey(from data: Data) -> SecKey? {
        return createKey(from: data, isPrivate: false)
    }
}
