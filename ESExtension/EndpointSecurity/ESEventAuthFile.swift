//
//  ESEventAuthFile.swift
//  ESExtension
//
//  Created by Doe Phương on 17/1/26.
//

import Darwin
import EndpointSecurity
import Foundation
import os

struct FileAuthEventContext: Sendable {
    var eventType: es_event_type_t
    var processPID: pid_t
    var processAuditToken: audit_token_t = audit_token_t()
    var signingID: String = "Unsigned/Unknown"
    var executablePath: String?
    var responsibleAuditToken: audit_token_t?
    var primaryPath: String
    var secondaryPath: String?
    var openFlags: Int32 = 0
    var isRenameToNewPath: Bool = false
    var renameNewDir: String?
    var renameNewFilename: String?
}

extension ESManager {

    func isAuthorized(
        processPID: pid_t,
        auditToken: audit_token_t,
        targetPath: String? = nil,
        secondaryPath: String? = nil
    ) -> Bool {
        if processPID == getpid() {
            return true
        }
        let callerUID = audit_token_to_euid(auditToken)
        if let path = targetPath, !isPathAllowedForUID(path, callerUID: callerUID) {
            return false
        }
        if let secPath = secondaryPath, !isPathAllowedForUID(secPath, callerUID: callerUID) {
            return false
        }
        if processIDLock.withLock({ processPID == authenticatedMainAppPID }) {
            return true
        }
        return CodeSignatureValidator.validate(
            auditToken: auditToken,
            requirement: CodeSignatureValidator.projectRootRequirement
        )
    }

    /// Ensures that inside `/Users/Shared/AppLocker/<UID>`, a non-root process can only mutate its own `<UID>` folder.
    func isPathAllowedForUID(_ rawPath: String, callerUID: uid_t) -> Bool {
        if callerUID == 0 { return true }
        let normalized = normalizeFirmlinkPath(rawPath)
        let prefix = "/Users/Shared/AppLocker/"
        guard normalized.hasPrefix(prefix) else { return true }
        let remainder = String(normalized.dropFirst(prefix.count))
        guard let firstComponent = remainder.split(separator: "/").first,
              let pathUID = uid_t(firstComponent) else {
            return true
        }
        return pathUID == callerUID
    }

    func isAuthorized(_ message: ESMessage) -> Bool {
        let auditToken = message.pointee.process.pointee.audit_token
        return isAuthorized(processPID: audit_token_to_pid(auditToken), auditToken: auditToken)
    }

    static func signingID(for message: ESMessage) -> String {
        string(from: message.pointee.process.pointee.signing_id) ?? "Unsigned/Unknown"
    }

    func makeFileAuthContext(
        eventType: es_event_type_t,
        message: ESMessage,
        primaryPath: String,
        secondaryPath: String? = nil,
        openFlags: Int32 = 0
    ) -> FileAuthEventContext {
        let proc = message.pointee.process.pointee
        let token = proc.audit_token
        return FileAuthEventContext(
            eventType: eventType,
            processPID: audit_token_to_pid(token),
            processAuditToken: token,
            signingID: Self.signingID(for: message),
            executablePath: string(from: proc.executable.pointee.path),
            responsibleAuditToken: proc.responsible_audit_token,
            primaryPath: primaryPath,
            secondaryPath: secondaryPath,
            openFlags: openFlags
        )
    }

    func evaluateFileAuth(context: FileAuthEventContext, valve: any ESAuthResponding) {
        switch context.eventType {
        case ES_EVENT_TYPE_AUTH_OPEN: evaluateAuthOpen(context: context, valve: valve)
        case ES_EVENT_TYPE_AUTH_UNLINK: evaluateAuthUnlink(context: context, valve: valve)
        case ES_EVENT_TYPE_AUTH_RENAME: evaluateAuthRename(context: context, valve: valve)
        case ES_EVENT_TYPE_AUTH_TRUNCATE: evaluateAuthTruncate(context: context, valve: valve)
        case ES_EVENT_TYPE_AUTH_EXCHANGEDATA: evaluateAuthExchangedata(context: context, valve: valve)
        case ES_EVENT_TYPE_AUTH_CLONE: evaluateAuthClone(context: context, valve: valve)
        case ES_EVENT_TYPE_AUTH_LINK: evaluateAuthLink(context: context, valve: valve)
        default: _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
        }
    }

    func handleAuthOpen(client: OpaquePointer, message: ESMessage, valve: ESSafetyValve) {
        let path = string(from: message.pointee.event.open.file.pointee.path) ?? ESSafetyValve.path(for: message)
        let context = makeFileAuthContext(
            eventType: ES_EVENT_TYPE_AUTH_OPEN,
            message: message,
            primaryPath: path,
            openFlags: message.pointee.event.open.fflag
        )
        evaluateAuthOpen(context: context, valve: valve)
    }

    func evaluateAuthOpen(context: FileAuthEventContext, valve: any ESAuthResponding) {
        let path = context.primaryPath
        if isAppBundlePath(path) {
            handleAppBundleAuthOpen(context: context, valve: valve)
        } else if isProtectedConfigPath(path) {
            handleConfigFileAuthOpen(context: context, valve: valve)
        } else if isInsideProtectedFolder(path) {
            handleProtectedFolderAuthOpen(context: context, valve: valve)
        } else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
        }
    }

    func isWriteIntent(_ fflag: Int32) -> Bool {
        let fWrite = Int32(0x00000002)
        let modifyBits = Int32(O_CREAT) | Int32(O_TRUNC) | Int32(O_APPEND)
        return (fflag & fWrite) != 0 || (fflag & modifyBits) != 0
    }

    private func handleAppBundleAuthOpen(context: FileAuthEventContext, valve: any ESAuthResponding) {
        let path = context.primaryPath
        let sigID = context.signingID
        if !isWriteIntent(context.openFlags) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            Logfile.endpointSecurity.debug(
                "[AuthFile] OPEN ALLOW (Read-only): \(path, privacy: .public) (\(sigID, privacy: .public))"
            )
            return
        }
        if isAuthorized(processPID: context.processPID, auditToken: context.processAuditToken) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            Logfile.endpointSecurity.debug(
                "[AuthFile] OPEN ALLOW (Write-Intent): \(path, privacy: .public) (\(sigID, privacy: .public))"
            )
            return
        }
        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        Logfile.endpointSecurity.warning(
            "[AuthFile] OPEN DENY (Write-Intent): \(path, privacy: .public) (\(sigID, privacy: .public))"
        )
    }

    private func handleConfigFileAuthOpen(context: FileAuthEventContext, valve: any ESAuthResponding) {
        if !isWriteIntent(context.openFlags) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            return
        }
        if isAuthorized(
            processPID: context.processPID,
            auditToken: context.processAuditToken,
            targetPath: context.primaryPath
        ) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            return
        }
        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        let isTruncate = (context.openFlags & Int32(O_TRUNC)) != 0
        logConfigTamperBlocked(context: context, action: isTruncate ? "Truncate" : "Write")
        Logfile.endpointSecurity.warning(
            "[AuthFile] PRIVACY_LOCK [OPEN] DENY write to config: \(context.primaryPath, privacy: .public)"
        )
    }

    private func handleProtectedFolderAuthOpen(context: FileAuthEventContext, valve: any ESAuthResponding) {
        let path = context.primaryPath
        let filename = (path as NSString).lastPathComponent
        if filename == ".DS_Store" || filename == ".localized" || filename.hasPrefix(".com.apple.") {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            return
        }
        guard isWriteIntent(context.openFlags) else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            return
        }
        if isAuthorized(
            processPID: context.processPID,
            auditToken: context.processAuditToken,
            targetPath: path
        ) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            return
        }
        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        Logfile.endpointSecurity.warning(
            "[AuthFile] OPEN DENY (Folder Write): \(path, privacy: .public) (\(context.signingID, privacy: .public))"
        )
    }
}
