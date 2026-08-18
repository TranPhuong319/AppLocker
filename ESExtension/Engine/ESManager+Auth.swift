//
//  ESManager+Auth.swift
//  ESExtension
//
//  Created by Doe Phương on 9/1/26.
//

import CryptoKit
import Foundation
import os
import Security

extension ESManager: ESAppProtocol {

    /// Dynamic CDHash & path validation for calling XPC process
    func isCallerBinaryValid(connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier

        // 1. Get process path
        guard let callerPath = getProcessPath(for: pid) else {
            Logfile.endpointSecurity.error("Auth: Failed to retrieve process path for pid=\(pid)")
            return false
        }

        // 2. Validate path (Must belong to AppLocker executable)
        guard callerPath.hasSuffix("/Contents/MacOS/AppLocker") else {
            Logfile.endpointSecurity.error("Auth: Rejected XPC caller with unauthorized path: \(callerPath)")
            return false
        }

        // 3. Retrieve caller CDHash from OS Kernel via auditToken
        guard let callerCDHash = getCDHash(for: connection) else {
            Logfile.endpointSecurity.error("Auth: Failed to retrieve caller CDHash from auditToken")
            return false
        }

        // 4. Retrieve CDHash of the app binary on disk at the verified path
        guard let diskCDHash = getCDHash(forFilePath: callerPath) else {
            Logfile.endpointSecurity.error("Auth: Failed to retrieve disk binary CDHash for path: \(callerPath)")
            return false
        }

        // 5. Dynamic match check
        guard callerCDHash == diskCDHash else {
            Logfile.endpointSecurity.error("Auth: CDHash mismatch between running process and disk binary!")
            return false
        }

        return true
    }

    private func getCDHash(for connection: NSXPCConnection) -> Data? {
        var auditToken = connection.esAuditToken
        let tokenData = Data(bytes: &auditToken, count: MemoryLayout<audit_token_t>.size)
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary

        var secCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &secCode) == errSecSuccess,
              let code = secCode else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticRef = staticCode else { return nil }

        var dictionary: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSInternalInformation)
        guard SecCodeCopySigningInformation(staticRef, flags, &dictionary) == errSecSuccess,
              let info = dictionary as? [String: Any] else { return nil }

        return info[kSecCodeInfoUnique as String] as? Data
    }

    private func getCDHash(forFilePath path: String) -> Data? {
        let url = URL(fileURLWithPath: path)
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }

        var dictionary: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSInternalInformation)
        guard SecCodeCopySigningInformation(code, flags, &dictionary) == errSecSuccess,
              let info = dictionary as? [String: Any] else { return nil }

        return info[kSecCodeInfoUnique as String] as? Data
    }

    private func getProcessPath(for pid: pid_t) -> String? {
        let pathBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MAXPATHLEN))
        defer { pathBuffer.deallocate() }
        let length = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
        guard length > 0 else { return nil }
        return String(cString: pathBuffer)
    }

    public func authenticate(
        clientNonce: Data,
        clientSig: Data,
        clientPublicKey: Data,
        withReply reply: @escaping (Data?, Data?, Data?, Bool) -> Void
    ) {
        guard let conn = NSXPCConnection.current() else {
            Logfile.endpointSecurity.error("Auth: No current XPC connection")
            reply(nil, nil, nil, false)
            return
        }

        Logfile.endpointSecurity.log("Auth: Received authentication request from pid=\(conn.processIdentifier)")

        // 0. Validate caller binary and dynamic CDHash
        guard isCallerBinaryValid(connection: conn) else {
            Logfile.endpointSecurity.error("Auth: Caller binary or CDHash validation failed!")
            reply(nil, nil, nil, false)
            return
        }

        // 1. Verify Client Signature (Fast - no I/O)
        guard KeychainHelper.shared.verify(
            signature: clientSig, originalData: clientNonce, publicKeyData: clientPublicKey
        ) else {
            Logfile.endpointSecurity.error("Auth: Client signature verification failed!")
            reply(nil, nil, nil, false)
            return
        }

        // 2. Ensure Server Keys exist (gen synchronously in ~0.1ms if needed)
        let serverTag = KeychainHelper.Keys.extensionPublic
        if !KeychainHelper.shared.hasKey(tag: serverTag) {
            do {
                try KeychainHelper.shared.generateKeys(tag: serverTag)
            } catch {
                Logfile.endpointSecurity.error("Auth: Key generation failed: \(error)")
                reply(nil, nil, nil, false)
                return
            }
        }

        // 3. Sign Challenge (clientNonce + serverNonce)
        let serverNonce = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let combinedData = clientNonce + serverNonce

        guard let serverSig = KeychainHelper.shared.sign(data: combinedData, tag: serverTag),
              let serverPubKeyData = KeychainHelper.shared.exportPublicKey(tag: serverTag) else {
            Logfile.endpointSecurity.error("Auth: Failed to sign server response.")
            reply(nil, nil, nil, false)
            return
        }

        // 4. Mark Connection as Authenticated & Cache PID
        let connID = ObjectIdentifier(conn)
        _ = xpcConnectionLock.withLock {
            authenticatedConnections.insert(connID)
        }

        cacheMainAppPID(from: conn)
        Logfile.endpointSecurity.log("Auth: Connection authenticated.")

        // Flush pending notifications NOW that the connection is fully authenticated.
        flushPendingNotifications(to: conn)

        reply(serverNonce, serverSig, serverPubKeyData, true)
    }

    public func processPendingApps(
        approvedPIDs: [Int32],
        rejectedPIDs: [Int32],
        withReply reply: @escaping (Bool) -> Void
    ) {
        guard isCurrentConnectionAuthenticated() else {
            Logfile.endpointSecurity.error("processPendingApps: Connection not authenticated")
            reply(false)
            return
        }

        Logfile.endpointSecurity.log("processPendingApps: Approved PIDs \(approvedPIDs), Rejected PIDs \(rejectedPIDs)")
        let result = processPendingBatch(approved: approvedPIDs, rejected: rejectedPIDs)
        reply(result)
    }
}
