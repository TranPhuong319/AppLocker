//
//  CodeSignatureValidator.swift
//  AppLocker
//
//  Created by Doe Phương on 16/9/26.
//

import Darwin
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

    /// Validates an audit token against a specific SecRequirement with strict flags.
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
            let pid = audit_token_to_pid(auditToken)
            let path = executablePath(for: pid)
            Logfile.esSecurity.error(
                """
                [CodeSignValidator] SecCodeCopyGuestWithAttributes failed for PID \(pid, privacy: .public) \
                at \(path, privacy: .public): status=\(copyStatus, privacy: .public)
                """
            )
            return false
        }

        // Strict code validity verification for live process
        let strictFlags = SecCSFlags(rawValue: kSecCSStrictValidate)
        let checkStatus = SecCodeCheckValidity(code, strictFlags, requirement)
        guard checkStatus == errSecSuccess else {
            let pid = audit_token_to_pid(auditToken)
            let path = executablePath(for: pid)
            let desc = (SecCopyErrorMessageString(checkStatus, nil) as String?) ?? "OSStatus \(checkStatus)"
            Logfile.esSecurity.error(
                """
                [CodeSignValidator] SecCodeCheckValidity failed for PID \(pid, privacy: .public) \
                at \(path, privacy: .public): status=\(checkStatus, privacy: .public) (\(desc, privacy: .public))
                """
            )
            return false
        }

        return true
    }

    /// Safely resolves the filesystem executable path for a process identifier.
    public static func executablePath(for pid: pid_t) -> String {
        guard pid > 0 else { return "PID 0 (Kernel)" }
        var pathBuffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
        if length > 0, let path = String(bytes: pathBuffer.prefix(Int(length)), encoding: .utf8) {
            return path
        }
        return "Unknown (terminated or permission denied)"
    }

    /// Validates an NSXPCConnection caller against the main app requirement.
    public static func validateXPCConnection(_ connection: NSXPCConnection) -> Bool {
        let token = connection.auditToken
        let pid = connection.processIdentifier

        // 1. Strict Code Signature Validation against Main App Requirement
        guard validate(auditToken: token, requirement: mainAppRequirement) else {
            Logfile.esSecurity.error(
                "[CodeSignValidator] XPC caller signature validation failed for PID \(pid, privacy: .public)"
            )
            return false
        }

        return true
    }
}
