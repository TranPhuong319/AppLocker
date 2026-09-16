//
//  CodeSignatureValidator.swift
//  AppLocker
//
//  Created by Doe Phương on 16/9/26.
//

import Foundation
import Security
import os

/// Cryptographic code signature validator for XPC callers and Endpoint Security events.
public enum CodeSignatureValidator: Sendable {

    /// Precompiled requirement for the main GUI app (XPC Handshake).
    public nonisolated(unsafe) static let mainAppRequirement: SecRequirement? = {
        let reqString = """
        identifier "com.TranPhuong319.AppLocker" and \
        certificate root = H"de0cad38fcd90bf4e60bd946a23c9c13dea878f8"
        """
        var req: SecRequirement?
        SecRequirementCreateWithString(reqString as CFString, [], &req)
        return req
    }()

    /// Precompiled requirement for any project binary (App, ESExtension, Sparkle Autoupdate).
    public nonisolated(unsafe) static let projectRootRequirement: SecRequirement? = {
        let reqString = """
        certificate root = H"de0cad38fcd90bf4e60bd946a23c9c13dea878f8"
        """
        var req: SecRequirement?
        SecRequirementCreateWithString(reqString as CFString, [], &req)
        return req
    }()

    /// Validates an audit token against a specific SecRequirement.
    public static func validate(auditToken: audit_token_t, requirement: SecRequirement?) -> Bool {
        guard let requirement else {
            Logfile.esSecurity.error("[CodeSignValidator] SecRequirement is nil")
            return false
        }

        var token = auditToken
        let tokenData = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
        let attributes: [CFString: Any] = [kSecGuestAttributeAudit: tokenData]

        var guestCode: SecCode?
        let copyStatus = SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &guestCode)
        guard copyStatus == errSecSuccess, let code = guestCode else {
            return false
        }

        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    /// Validates an NSXPCConnection caller against the main app requirement.
    public static func validateXPCConnection(_ connection: NSXPCConnection) -> Bool {
        validate(auditToken: connection.auditToken, requirement: mainAppRequirement)
    }
}
