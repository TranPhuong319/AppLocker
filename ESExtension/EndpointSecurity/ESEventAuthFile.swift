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

        // Allow read-only access and let kernel cache the result
        if !isWriteIntent(message.pointee.event.open.fflag) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            return
        }

        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        let isTruncate = (message.pointee.event.open.fflag & Int32(O_TRUNC)) != 0
        logConfigTamperBlocked(message: message, action: isTruncate ? "Truncate" : "Write")
        Logfile.endpointSecurity.warning(
            "[AuthFile] PRIVACY_LOCK [OPEN] DENY write to config: \(path, privacy: .public)"
        )
    }

    private func handleProtectedFolderAuthOpen(
        path: String,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let filename = (path as NSString).lastPathComponent
        if filename == ".DS_Store" || filename == ".localized" || filename.hasPrefix(".com.apple.") {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            return
        }

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
        if let targetPath = string(from: targetToken) {
            let filename = (targetPath as NSString).lastPathComponent
            if filename == ".DS_Store" || filename == ".localized" || filename.hasPrefix(".com.apple.") {
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
                return
            }
        }
        let isConfig = isProtectedConfigPath(targetToken)
        let isProtected = isConfig ||
                          isInsideProtectedFolder(targetToken) ||
                          isAppBundlePath(targetToken)
        handleProtectedMutationAuth(
            message: message,
            valve: valve,
            isTargetProtected: isProtected,
            isConfig: isConfig,
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
        let isConfig = isProtectedConfigPath(srcPathToken)
        let srcIsProtected = isConfig ||
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
        if isConfig {
            let action = isTrashDestination(renameEvent) ? "Delete" : "Rename"
            logConfigTamperBlocked(message: message, action: action)
        }
        Logfile.endpointSecurity.warning(
            "[AuthFile] SELF_PROT [RENAME] DENY (Protected): (Process: \(procID, privacy: .public))"
        )
    }

    private func isTrashDestination(_ renameEvent: es_event_rename_t) -> Bool {
        if renameEvent.destination_type == ES_DESTINATION_TYPE_EXISTING_FILE {
            if let dstPath = string(from: renameEvent.destination.existing_file.pointee.path) {
                return dstPath.contains("/.Trash") || dstPath.contains("/.Trashes")
            }
        } else if renameEvent.destination_type == ES_DESTINATION_TYPE_NEW_PATH {
            if let dirPath = string(from: renameEvent.destination.new_path.dir.pointee.path) {
                return dirPath.contains("/.Trash") || dirPath.contains("/.Trashes")
            }
        }
        return false
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
        let isConfig = isProtectedConfigPath(targetToken)
        let isProtected = isConfig ||
                          isInsideProtectedFolder(targetToken) ||
                          isAppBundlePath(targetToken)
        handleProtectedMutationAuth(
            message: message,
            valve: valve,
            isTargetProtected: isProtected,
            isConfig: isConfig,
            operationName: "TRUNCATE"
        )
    }

    // MARK: - Extended Events (Santa Style Protection)

    private func handleProtectedMutationAuth(
        message: ESMessage,
        valve: ESSafetyValve,
        isTargetProtected: Bool,
        isConfig: Bool = false,
        operationName: String
    ) {
        if isTargetProtected {
            let procID = Self.signingID(for: message)
            guard isAuthorized(message) else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                if isConfig {
                    let action: String = {
                        switch operationName {
                        case "UNLINK": return "Delete"
                        case "RENAME": return "Rename"
                        case "TRUNCATE": return "Truncate"
                        default: return "Write"
                        }
                    }()
                    logConfigTamperBlocked(message: message, action: action)
                }
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

    private func logConfigTamperBlocked(message: ESMessage, action: String) {
        let processPtr = message.pointee.process.pointee
        let senderPid = audit_token_to_pid(processPtr.audit_token)
        let senderPath = string(from: processPtr.executable.pointee.path)
            ?? processPath(for: senderPid)
            ?? "PID \(senderPid)"
        let responsiblePid = audit_token_to_pid(processPtr.responsible_audit_token)
        let responsiblePath = processPath(for: responsiblePid)
        let senderDisplayName: String = {
            if let respPath = responsiblePath, respPath.contains(".app") {
                return self.computeAppName(forExecPath: respPath)
            }
            if senderPath.starts(with: "/") {
                return self.computeAppName(forExecPath: senderPath)
            }
            return senderPath
        }()

        Logfile.endpointSecurity.warning(
            """
            [SecurityEvent:TamperBlocked] Target: Config (PID 0) | Sender: \(senderDisplayName, privacy: .public) \
            (PID \(senderPid, privacy: .public)) | Action: \(action, privacy: .public) \
            | SenderPath: \(senderPath, privacy: .public)
            """
        )
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
