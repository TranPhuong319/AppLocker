//
//  ESEventAuthFile+Mutation.swift
//  ESExtension
//
//  Created by Doe Phương on 4/11/26.
//

import Darwin
import EndpointSecurity
import Foundation
import os

// MARK: - File Mutation & Extended Tamper Resistance (UNLINK, RENAME, TRUNCATE, EXCHANGEDATA, CLONE, LINK)

extension ESManager {

    func handleAuthUnlink(client: OpaquePointer, message: ESMessage, valve: ESSafetyValve) {
        let targetPath = string(from: message.pointee.event.unlink.target.pointee.path) ?? ""
        let ctx = makeFileAuthContext(eventType: ES_EVENT_TYPE_AUTH_UNLINK, message: message, primaryPath: targetPath)
        evaluateAuthUnlink(context: ctx, valve: valve)
    }

    func evaluateAuthUnlink(context: FileAuthEventContext, valve: any ESAuthResponding) {
        let targetPath = context.primaryPath
        if !targetPath.isEmpty {
            let filename = (targetPath as NSString).lastPathComponent
            if filename == ".DS_Store" || filename == ".localized" || filename.hasPrefix(".com.apple.") {
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
                return
            }
        }
        let isConfig = isProtectedConfigPath(targetPath)
        let isProtected = isConfig || isInsideProtectedFolder(targetPath) || isAppBundlePath(targetPath)
        handleProtectedMutationAuth(
            context: context,
            valve: valve,
            isTargetProtected: isProtected,
            isConfig: isConfig,
            operationName: "UNLINK"
        )
    }

    func handleAuthRename(client: OpaquePointer, message: ESMessage, valve: ESSafetyValve) {
        let renameEvent = message.pointee.event.rename
        let srcPath = string(from: renameEvent.source.pointee.path) ?? ESSafetyValve.path(for: message)
        let isNewPath = (renameEvent.destination_type == ES_DESTINATION_TYPE_NEW_PATH)
        let existingDst: String? = (renameEvent.destination_type == ES_DESTINATION_TYPE_EXISTING_FILE)
            ? string(from: renameEvent.destination.existing_file.pointee.path)
            : nil
        var context = makeFileAuthContext(
            eventType: ES_EVENT_TYPE_AUTH_RENAME,
            message: message,
            primaryPath: srcPath,
            secondaryPath: existingDst
        )
        context.isRenameToNewPath = isNewPath
        context.renameNewDir = isNewPath ? string(from: renameEvent.destination.new_path.dir.pointee.path) : nil
        context.renameNewFilename = isNewPath ? string(from: renameEvent.destination.new_path.filename) : nil
        evaluateAuthRename(context: context, valve: valve)
    }

    func evaluateAuthRename(context: FileAuthEventContext, valve: any ESAuthResponding) {
        let srcPath = context.primaryPath
        let isConfig = isProtectedConfigPath(srcPath)
        let srcIsProtected = isConfig || isInsideProtectedFolder(srcPath) || isAppBundlePath(srcPath)
        let dstIsProtected = isRenameDestinationProtected(context)

        guard srcIsProtected || dstIsProtected else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            return
        }
        let procID = context.signingID
        let dstPathForCheck: String? = if context.isRenameToNewPath,
            let dir = context.renameNewDir, let name = context.renameNewFilename {
            (dir as NSString).appendingPathComponent(name)
        } else {
            context.secondaryPath
        }
        if isAuthorized(
            processPID: context.processPID,
            auditToken: context.processAuditToken,
            targetPath: srcPath,
            secondaryPath: dstPathForCheck
        ) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
            Logfile.endpointSecurity.debug(
                "[AuthFile] RENAME ALLOW: \(srcPath, privacy: .public) (\(procID, privacy: .public))"
            )
            return
        }
        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
        if isConfig {
            logConfigTamperBlocked(context: context, action: isTrashDestination(context) ? "Delete" : "Rename")
        }
        Logfile.endpointSecurity.warning(
            "[AuthFile] SELF_PROT [RENAME] DENY (Protected): (Process: \(procID, privacy: .public))"
        )
    }

    func isTrashDestination(_ context: FileAuthEventContext) -> Bool {
        if !context.isRenameToNewPath, let dstPath = context.secondaryPath {
            return dstPath.contains("/.Trash") || dstPath.contains("/.Trashes")
        }
        if context.isRenameToNewPath, let dirPath = context.renameNewDir {
            return dirPath.contains("/.Trash") || dirPath.contains("/.Trashes")
        }
        return false
    }

    private func isRenameDestinationProtected(_ context: FileAuthEventContext) -> Bool {
        if !context.isRenameToNewPath {
            guard let dstPath = context.secondaryPath else { return false }
            return isProtectedConfigPath(dstPath) || isInsideProtectedFolder(dstPath) || isAppBundlePath(dstPath)
        }
        guard let nameStr = context.renameNewFilename, let dirStr = context.renameNewDir else { return false }
        if isInsideProtectedFolder(dirStr) { return true }
        return nameStr == "AppLocker.app" && normalizeFirmlinkPath(dirStr) == "/Applications"
    }

    func handleAuthTruncate(client: OpaquePointer, message: ESMessage, valve: ESSafetyValve) {
        let targetPath = string(from: message.pointee.event.truncate.target.pointee.path) ?? ""
        let ctx = makeFileAuthContext(eventType: ES_EVENT_TYPE_AUTH_TRUNCATE, message: message, primaryPath: targetPath)
        evaluateAuthTruncate(context: ctx, valve: valve)
    }

    func evaluateAuthTruncate(context: FileAuthEventContext, valve: any ESAuthResponding) {
        let targetPath = context.primaryPath
        let isConfig = isProtectedConfigPath(targetPath)
        let isProtected = isConfig || isInsideProtectedFolder(targetPath) || isAppBundlePath(targetPath)
        handleProtectedMutationAuth(
            context: context,
            valve: valve,
            isTargetProtected: isProtected,
            isConfig: isConfig,
            operationName: "TRUNCATE"
        )
    }

    // MARK: - Extended Events (Google Santa Style Protection)

    func handleProtectedMutationAuth(
        context: FileAuthEventContext,
        valve: any ESAuthResponding,
        isTargetProtected: Bool,
        isConfig: Bool = false,
        operationName: String
    ) {
        guard isTargetProtected else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            return
        }
        let procID = context.signingID
        guard isAuthorized(
            processPID: context.processPID,
            auditToken: context.processAuditToken,
            targetPath: context.primaryPath,
            secondaryPath: context.secondaryPath
        ) else {
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            if isConfig {
                let action: String = switch operationName {
                case "UNLINK": "Delete"
                case "RENAME": "Rename"
                case "TRUNCATE": "Truncate"
                default: "Write"
                }
                logConfigTamperBlocked(context: context, action: action)
            }
            Logfile.endpointSecurity.warning(
                "[AuthFile] SELF_PROT [\(operationName)] DENY (Unauthorized): (Process: \(procID, privacy: .public))"
            )
            return
        }
        _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
        Logfile.endpointSecurity.debug(
            "[AuthFile] SELF_PROT [\(operationName)] ALLOW (Authorized): (Process: \(procID, privacy: .public))"
        )
    }

    func logConfigTamperBlocked(context: FileAuthEventContext, action: String) {
        let senderPid = context.processPID
        let senderPath = context.executablePath ?? processPath(for: senderPid) ?? "PID \(senderPid)"
        let responsiblePid = context.responsibleAuditToken.map { audit_token_to_pid($0) } ?? 0
        let responsiblePath = processPath(for: responsiblePid)
        let senderDisplayName: String = if let respPath = responsiblePath, respPath.contains(".app") {
            self.computeAppName(forExecPath: respPath)
        } else if senderPath.starts(with: "/") {
            self.computeAppName(forExecPath: senderPath)
        } else {
            senderPath
        }
        let responsiblePathArg = responsiblePath ?? ""
        Logfile.endpointSecurity.warning(
            """
            [SecurityEvent:TamperBlocked] Target: Config (PID 0) | Sender: \(senderDisplayName, privacy: .public) \
            (PID \(senderPid, privacy: .public)) | Action: \(action, privacy: .public) \
            | SenderPath: \(senderPath, privacy: .public) | ResponsiblePath: \(responsiblePathArg, privacy: .public)
            """
        )
    }

    func handleAuthExchangedata(client: OpaquePointer, message: ESMessage, valve: ESSafetyValve) {
        let exchange = message.pointee.event.exchangedata
        let file1 = string(from: exchange.file1.pointee.path) ?? ""
        let file2 = string(from: exchange.file2.pointee.path) ?? ""
        let ctx = makeFileAuthContext(
            eventType: ES_EVENT_TYPE_AUTH_EXCHANGEDATA, message: message, primaryPath: file1, secondaryPath: file2
        )
        evaluateAuthExchangedata(context: ctx, valve: valve)
    }

    func evaluateAuthExchangedata(context: FileAuthEventContext, valve: any ESAuthResponding) {
        let file1 = context.primaryPath
        let file2 = context.secondaryPath ?? ""
        let isProtected = isInsideProtectedFolder(file1) || isInsideProtectedFolder(file2) ||
                          isAppBundlePath(file1) || isAppBundlePath(file2)
        handleProtectedMutationAuth(
            context: context, valve: valve, isTargetProtected: isProtected, operationName: "EXCHANGE"
        )
    }

    func handleAuthClone(client: OpaquePointer, message: ESMessage, valve: ESSafetyValve) {
        let targetDir = string(from: message.pointee.event.clone.target_dir.pointee.path) ?? ""
        let source = string(from: message.pointee.event.clone.source.pointee.path) ?? ""
        let ctx = makeFileAuthContext(
            eventType: ES_EVENT_TYPE_AUTH_CLONE, message: message, primaryPath: targetDir, secondaryPath: source
        )
        evaluateAuthClone(context: ctx, valve: valve)
    }

    func evaluateAuthClone(context: FileAuthEventContext, valve: any ESAuthResponding) {
        let isProtected = isInsideProtectedFolder(context.primaryPath) || isAppBundlePath(context.secondaryPath ?? "")
        handleProtectedMutationAuth(
            context: context, valve: valve, isTargetProtected: isProtected, operationName: "CLONE"
        )
    }

    func handleAuthLink(client: OpaquePointer, message: ESMessage, valve: ESSafetyValve) {
        let linkEvent = message.pointee.event.link
        let targetDir = string(from: linkEvent.target_dir.pointee.path) ?? ""
        let source = string(from: linkEvent.source.pointee.path) ?? ""
        let ctx = makeFileAuthContext(
            eventType: ES_EVENT_TYPE_AUTH_LINK, message: message, primaryPath: targetDir, secondaryPath: source
        )
        evaluateAuthLink(context: ctx, valve: valve)
    }

    func evaluateAuthLink(context: FileAuthEventContext, valve: any ESAuthResponding) {
        let isProtected = isInsideProtectedFolder(context.primaryPath) || isAppBundlePath(context.secondaryPath ?? "")
        handleProtectedMutationAuth(
            context: context, valve: valve, isTargetProtected: isProtected, operationName: "LINK"
        )
    }
}
