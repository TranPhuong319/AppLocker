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

    static func isAuthorized(_ manager: ESManager, _ message: ESMessage) -> Bool {
        let mainAppID = "com.TranPhuong319.AppLocker"
        let extensionID = "com.TranPhuong319.AppLocker.ESExtension"

        // 1. Check PID (Fast Cache)
        let processPid = audit_token_to_pid(message.pointee.process.pointee.audit_token)
        if manager.processIDLock.withLock({ processPid == manager.authenticatedMainAppPID }) {
            return true
        }

        // 2. Get Calling Process Path
        let procPath = safePath(fromFilePointer: message.pointee.process.pointee.executable) ?? ""
        let isInsideBundle = procPath.hasPrefix("/Applications/AppLocker.app")

        // 3. Check Signing ID (Immutable Identity)
        let signingIDToken = message.pointee.process.pointee.signing_id
        if let signingID = string(from: signingIDToken) {
             if (signingID == mainAppID || signingID == extensionID) && isInsideBundle {
                 return true
             }
             // Sparkle Updates (Framework & Autoupdate tools)
             if signingID.lowercased().contains("sparkle") || signingID.hasPrefix("Autoupdate") {
                 if isInsideBundle { return true }

                 let parentAuditToken = message.pointee.process.pointee.parent_audit_token
                 let parentPid = audit_token_to_pid(parentAuditToken)
                 let mainAppPid = manager.processIDLock.withLock({ manager.authenticatedMainAppPID })

                 if parentPid != -1 && parentPid == mainAppPid {
                     if procPath.contains("/Library/Caches/") ||
                        procPath.contains("/var/folders/") ||
                        procPath.hasPrefix("/tmp/") ||
                        procPath.hasPrefix("/private/tmp/") {
                         return true
                     }
                 }
                 Logfile.endpointSecurity.warning(
                     """
                     [AuthFile] AUTH_CHECK [SPARKLE] Untrusted lineage or path: \(procPath, privacy: .public) \
                     (Parent PID: \(parentPid, privacy: .public), Main PID: \(mainAppPid ?? -1, privacy: .public))
                     """
                 )
             }
        }
        return false
    }

    static func getSigningID(_ message: ESMessage) -> String {
        let signingIDToken = message.pointee.process.pointee.signing_id
        if let idStr = string(from: signingIDToken) {
            return idStr
        }
        return "Unsigned/Unknown"
    }

    static func handleAuthOpen(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let path = ESSafetyValve.getPath(message)
        let esPath = message.pointee.event.open.file.pointee.path

        guard let manager = ESManager.sharedInstanceForCallbacks else {
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            return
        }

        if isAppBundlePath(esPath) {
            handleAppBundleAuthOpen(manager: manager, path: path, message: message, valve: valve)
        } else if isProtectedConfigPath(esPath) {
            handleConfigFileAuthOpen(manager: manager, path: path, message: message, valve: valve)
        } else if isInsideProtectedFolder(esPath) {
            handleProtectedFolderAuthOpen(manager: manager, path: path, message: message, valve: valve)
        } else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
        }
    }

    private static func handleAppBundleAuthOpen(
        manager: ESManager,
        path: String,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        if isAuthorized(manager, message) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            let sigID = getSigningID(message)
            Logfile.endpointSecurity.debug(
                """
                [AuthFile] SELF_PROT [OPEN] ALLOW (Authorized): \(path, privacy: .public) \
                (Process: \(sigID, privacy: .public))
                """
            )
            return
        }

        let fflag = message.pointee.event.open.fflag
        let fWrite = Int32(0x00000002)
        let modifyBits = Int32(O_CREAT) | Int32(O_TRUNC) | Int32(O_APPEND)
        let isWriteIntent = (fflag & fWrite) != 0 || (fflag & modifyBits) != 0

        if !isWriteIntent {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            let sigID = getSigningID(message)
            Logfile.endpointSecurity.debug(
                """
                [AuthFile] SELF_PROT [OPEN] ALLOW (Read-only): \(path, privacy: .public) \
                (Process: \(sigID, privacy: .public))
                """
            )
            return
        }

        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        let sigID = getSigningID(message)
        Logfile.endpointSecurity.warning(
            """
            [AuthFile] SELF_PROT [OPEN] DENY (Write-Intent): \(path, privacy: .public) \
            (Process: \(sigID, privacy: .public))
            """
        )
    }

    private static func handleConfigFileAuthOpen(
        manager: ESManager,
        path: String,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        if isAuthorized(manager, message) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            return
        }
        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        Logfile.endpointSecurity.warning(
            "[AuthFile] PRIVACY_LOCK [OPEN] DENY access to config: \(path, privacy: .public)"
        )
    }

    private static func handleProtectedFolderAuthOpen(
        manager: ESManager,
        path: String,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let fflag = message.pointee.event.open.fflag
        let fWrite = Int32(0x00000002)
        let modifyBits = Int32(O_CREAT) | Int32(O_TRUNC) | Int32(O_APPEND)
        let isWriteIntent = (fflag & fWrite) != 0 || (fflag & modifyBits) != 0

        if isWriteIntent {
            if isAuthorized(manager, message) {
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
                return
            }
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            let sigID = getSigningID(message)
            Logfile.endpointSecurity.warning(
                """
                [AuthFile] SELF_PROT [OPEN] DENY folder write-intent: \(path, privacy: .public) \
                (Process: \(sigID, privacy: .public))
                """
            )
            return
        }
        _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
    }

    static func handleAuthUnlink(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let targetPathToken = message.pointee.event.unlink.target.pointee.path
        let isFileProtected = isProtectedConfigPath(targetPathToken)
        let isFolderProtected = isInsideProtectedFolder(targetPathToken)
        let isAppProtected = isAppBundlePath(targetPathToken)

        if isFileProtected || isFolderProtected || isAppProtected {
            let path = ESSafetyValve.getPath(message)
            guard let manager = ESManager.sharedInstanceForCallbacks else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                return
            }
            if isAuthorized(manager, message) {
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
                let sigID = getSigningID(message)
                Logfile.endpointSecurity.debug(
                    """
                    [AuthFile] SELF_PROT [UNLINK] ALLOW (Authorized): \(path, privacy: .public) \
                    (Process: \(sigID, privacy: .public))
                    """
                )
                return
            }
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            let procID = getSigningID(message)
            Logfile.endpointSecurity.warning(
                """
                [AuthFile] SELF_PROT [UNLINK] DENY (Protected): \(path, privacy: .public) \
                (Process: \(procID, privacy: .public))
                """
            )
        } else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
        }
    }

    static func handleAuthRename(
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

        if srcIsProtected || dstIsProtected {
            guard let manager = ESManager.sharedInstanceForCallbacks else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                return
            }
            let procID = getSigningID(message)
            if isAuthorized(manager, message) {
                let path = ESSafetyValve.getPath(message)
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
                Logfile.endpointSecurity.debug(
                    """
                    [AuthFile] SELF_PROT [RENAME] ALLOW (Authorized): \(path, privacy: .public) \
                    (Process: \(procID, privacy: .public))
                    """
                )
                return
            }
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            Logfile.endpointSecurity.warning(
                "[AuthFile] SELF_PROT [RENAME] DENY (Protected): (Process: \(procID, privacy: .public))"
            )
        } else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
        }
    }

    private static func isRenameDestinationProtected(_ renameEvent: es_event_rename_t) -> Bool {
        if renameEvent.destination_type == ES_DESTINATION_TYPE_EXISTING_FILE {
            let dstToken = renameEvent.destination.existing_file.pointee.path
            return isProtectedConfigPath(dstToken) ||
                   isInsideProtectedFolder(dstToken) ||
                   isAppBundlePath(dstToken)
        } else if renameEvent.destination_type == ES_DESTINATION_TYPE_NEW_PATH {
            let filenameToken = renameEvent.destination.new_path.filename
            if let nameStr = string(from: filenameToken) {
                let isParentProtected = isInsideProtectedFolder(renameEvent.destination.new_path.dir.pointee.path)
                if isParentProtected {
                    return true
                } else if nameStr == "AppLocker.app" {
                    let dirToken = renameEvent.destination.new_path.dir.pointee.path
                    if let dirStr = string(from: dirToken), dirStr == "/Applications" {
                        return true
                    }
                }
            }
        }
        return false
    }

    static func handleAuthTruncate(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let targetToken = message.pointee.event.truncate.target.pointee.path
        if isProtectedConfigPath(targetToken) || isInsideProtectedFolder(targetToken) || isAppBundlePath(targetToken) {
            guard let manager = ESManager.sharedInstanceForCallbacks else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                return
            }
            let procID = getSigningID(message)
            if isAuthorized(manager, message) {
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
                Logfile.endpointSecurity.debug(
                    "[AuthFile] SELF_PROT [TRUNCATE] ALLOW (Authorized): (Process: \(procID, privacy: .public))"
                )
                return
            }
            let path = ESSafetyValve.getPath(message)
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            Logfile.endpointSecurity.warning(
                """
                [AuthFile] SELF_PROT [TRUNCATE] DENY (Protected): \(path, privacy: .public) \
                (Process: \(procID, privacy: .public))
                """
            )
        } else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
        }
    }

    // MARK: - Extended Events (Santa Style Protection)

    private static func handleProtectedMutationAuth(
        message: ESMessage,
        valve: ESSafetyValve,
        isTargetProtected: Bool,
        operationName: String
    ) {
        if isTargetProtected {
            let procID = getSigningID(message)
            guard let manager = ESManager.sharedInstanceForCallbacks, isAuthorized(manager, message) else {
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

    static func handleAuthExchangedata(
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

    static func handleAuthClone(
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

    static func handleAuthLink(
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
