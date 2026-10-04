//
//  ESEventAuthFile.swift
//  ESExtension
//
//  Created by Doe Phương on 17/1/26.
//

import EndpointSecurity
import Foundation
import os
import Darwin

extension ESManager {

    func isAuthorized(_ message: ESMessage) -> Bool {
        // 1. Fast Cache (PID verified via XPC handshake or self)
        let processPid = audit_token_to_pid(message.pointee.process.pointee.audit_token)
        if processPid == getpid() || processIDLock.withLock({ processPid == authenticatedMainAppPID }) {
            return true
        }

        // 2. Cryptographic Code Signature Verification (AppLocker, ESExtension, Sparkle Autoupdate)
        let auditToken = message.pointee.process.pointee.audit_token
        if CodeSignatureValidator.validate(
            auditToken: auditToken,
            requirement: CodeSignatureValidator.projectRootRequirement
        ) {
            return true
        }

        return false
    }

    static func signingID(for message: ESMessage) -> String {
        string(from: message.pointee.process.pointee.signing_id) ?? "Unsigned/Unknown"
    }

    func handleAuthOpen(client: OpaquePointer, message: ESMessage, valve: ESSafetyValve) {
        let path = ESSafetyValve.path(for: message)
        let esPath = message.pointee.event.open.file.pointee.path

        if isAppBundlePath(esPath) {
            handleAppBundleAuthOpen(path: path, message: message, valve: valve)
        } else if isProtectedConfigPath(esPath) {
            handleConfigFileAuthOpen(path: path, message: message, valve: valve)
        } else if isInsideProtectedFolder(esPath) {
            handleProtectedFolderAuthOpen(path: path, message: message, valve: valve)
        } else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
        }
    }

    private func isWriteIntent(_ fflag: Int32) -> Bool {
        let fWrite = Int32(0x00000002)
        let modifyBits = Int32(O_CREAT) | Int32(O_TRUNC) | Int32(O_APPEND)
        return (fflag & fWrite) != 0 || (fflag & modifyBits) != 0
    }

    private func handleAppBundleAuthOpen(
        path: String,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        if isAuthorized(message) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            let sigID = Self.signingID(for: message)
            Logfile.endpointSecurity.debug(
                "[AuthFile] OPEN ALLOW: \(path, privacy: .public) (\(sigID, privacy: .public))"
            )
            return
        }

        if !isWriteIntent(message.pointee.event.open.fflag) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            let sigID = Self.signingID(for: message)
            Logfile.endpointSecurity.debug(
                "[AuthFile] OPEN ALLOW (Read-only): \(path, privacy: .public) (\(sigID, privacy: .public))"
            )
            return
        }

        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        let sigID = Self.signingID(for: message)
        Logfile.endpointSecurity.warning(
            "[AuthFile] OPEN DENY (Write-Intent): \(path, privacy: .public) (\(sigID, privacy: .public))"
        )
    }

    private func handleConfigFileAuthOpen(
        path: String,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        if isAuthorized(message) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            return
        }
        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        Logfile.endpointSecurity.warning(
            "[AuthFile] PRIVACY_LOCK [OPEN] DENY access to config: \(path, privacy: .public)"
        )
    }

    private func handleProtectedFolderAuthOpen(
        path: String,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        guard isWriteIntent(message.pointee.event.open.fflag) else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            return
        }

        if isAuthorized(message) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            return
        }

        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        let sigID = Self.signingID(for: message)
        Logfile.endpointSecurity.warning(
            "[AuthFile] OPEN DENY (Folder Write): \(path, privacy: .public) (\(sigID, privacy: .public))"
        )
    }

    func handleAuthUnlink(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let targetToken = message.pointee.event.unlink.target.pointee.path
        let isProtected = isProtectedConfigPath(targetToken) ||
                          isInsideProtectedFolder(targetToken) ||
                          isAppBundlePath(targetToken)
        handleProtectedMutationAuth(
            message: message,
            valve: valve,
            isTargetProtected: isProtected,
            operationName: "UNLINK"
        )
    }

    func handleAuthRename(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let renameEvent = message.pointee.event.rename
        let srcPathToken = renameEvent.source.pointee.path
        let srcIsProtected = isProtectedConfigPath(srcPathToken) ||
                             isInsideProtectedFolder(srcPathToken) ||
                             isAppBundlePath(srcPathToken)
        let dstIsProtected = isRenameDestinationProtected(renameEvent)

        guard srcIsProtected || dstIsProtected else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            return
        }

        let procID = Self.signingID(for: message)
        if isAuthorized(message) {
            let path = ESSafetyValve.path(for: message)
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            Logfile.endpointSecurity.debug(
                "[AuthFile] RENAME ALLOW: \(path, privacy: .public) (\(procID, privacy: .public))"
            )
            return
        }

        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        Logfile.endpointSecurity.warning(
            "[AuthFile] SELF_PROT [RENAME] DENY (Protected): (Process: \(procID, privacy: .public))"
        )
    }

    private func isRenameDestinationProtected(_ renameEvent: es_event_rename_t) -> Bool {
        if renameEvent.destination_type == ES_DESTINATION_TYPE_EXISTING_FILE {
            let dstToken = renameEvent.destination.existing_file.pointee.path
            return isProtectedConfigPath(dstToken) ||
                   isInsideProtectedFolder(dstToken) ||
                   isAppBundlePath(dstToken)
        }

        guard renameEvent.destination_type == ES_DESTINATION_TYPE_NEW_PATH,
              let nameStr = string(from: renameEvent.destination.new_path.filename) else {
            return false
        }

        let dirToken = renameEvent.destination.new_path.dir.pointee.path
        if isInsideProtectedFolder(dirToken) {
            return true
        }

        if nameStr == "AppLocker.app", let dirStr = string(from: dirToken), dirStr == "/Applications" {
            return true
        }

        return false
    }

    func handleAuthTruncate(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let targetToken = message.pointee.event.truncate.target.pointee.path
        let isProtected = isProtectedConfigPath(targetToken) ||
                          isInsideProtectedFolder(targetToken) ||
                          isAppBundlePath(targetToken)
        handleProtectedMutationAuth(
            message: message,
            valve: valve,
            isTargetProtected: isProtected,
            operationName: "TRUNCATE"
        )
    }

    // MARK: - Extended Events (Santa Style Protection)

    private func handleProtectedMutationAuth(
        message: ESMessage,
        valve: ESSafetyValve,
        isTargetProtected: Bool,
        operationName: String
    ) {
        if isTargetProtected {
            let procID = Self.signingID(for: message)
            guard isAuthorized(message) else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                Logfile.endpointSecurity.warning(
                    """
                    [AuthFile] SELF_PROT [\(operationName)] DENY (Unauthorized): \
                    (Process: \(procID, privacy: .public))
                    """
                )
                return
            }
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            Logfile.endpointSecurity.debug(
                """
                [AuthFile] SELF_PROT [\(operationName)] ALLOW (Authorized): \
                (Process: \(procID, privacy: .public))
                """
            )
            return
        }
        _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
    }

    func handleAuthExchangedata(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let exchange = message.pointee.event.exchangedata
        let isProtected = isInsideProtectedFolder(exchange.file1.pointee.path) ||
                          isInsideProtectedFolder(exchange.file2.pointee.path) ||
                          isAppBundlePath(exchange.file1.pointee.path) ||
                          isAppBundlePath(exchange.file2.pointee.path)
        handleProtectedMutationAuth(
            message: message,
            valve: valve,
            isTargetProtected: isProtected,
            operationName: "EXCHANGE"
        )
    }

    func handleAuthClone(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let isProtected = isInsideProtectedFolder(message.pointee.event.clone.target_dir.pointee.path) ||
                          isAppBundlePath(message.pointee.event.clone.source.pointee.path)
        handleProtectedMutationAuth(
            message: message,
            valve: valve,
            isTargetProtected: isProtected,
            operationName: "CLONE"
        )
    }

    func handleAuthLink(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let linkEvent = message.pointee.event.link
        let isProtected = isInsideProtectedFolder(linkEvent.target_dir.pointee.path) ||
                          isAppBundlePath(linkEvent.source.pointee.path)
        handleProtectedMutationAuth(
            message: message,
            valve: valve,
            isTargetProtected: isProtected,
            operationName: "LINK"
        )
    }
}
