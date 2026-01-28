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

    static func isSharedPath(_ esPath: es_string_token_t) -> Bool {
        guard let data = esPath.data else { return false }
        let len = Int(esPath.length)
        // "/Users/Shared" is 13 chars
        let prefixLen = 13
        if len < prefixLen { return false }

        let prefix: [UInt8] = [
            0x2f, 0x55, 0x73, 0x65, 0x72, 0x73, 0x2f, 0x53, 0x68, 0x61, 0x72, 0x65, 0x64
        ]
        return memcmp(data, prefix, prefixLen) == 0
    }

    /// Checks if path IS or IS INSIDE /Users/Shared/AppLocker
    static func isInsideProtectedFolder(
        _ esPath: es_string_token_t
    ) -> Bool {
        guard let data = esPath.data else { return false }
        let len = Int(esPath.length)
        let prefix: [UInt8] = [
            0x2f, 0x55, 0x73, 0x65, 0x72, 0x73, 0x2f, 0x53, 0x68, 0x61, 0x72, 0x65, 0x64, 0x2f,
            0x41, 0x70, 0x70, 0x4c, 0x6f, 0x63, 0x6b, 0x65, 0x72
        ]  // "/Users/Shared/AppLocker"
        let prefixLen = 23

        if len < prefixLen { return false }

        // Check prefix
        if memcmp(data, prefix, prefixLen) == 0 {
            // Exact match (/Users/Shared/AppLocker)
            if len == prefixLen { return true }
            // Subpath match (/Users/Shared/AppLocker/...)
            // Next char must be '/'
            if data.advanced(by: prefixLen).pointee == 0x2f {
                return true
            }
        }
        return false
    }

    static func isProtectedConfigPath(
        _ esPath: es_string_token_t
    ) -> Bool {
        guard let data = esPath.data else { return false }
        let len = Int(esPath.length)
        let suffix: [UInt8] = [
            0x2f, 0x41, 0x70, 0x70, 0x4c, 0x6f, 0x63, 0x6b, 0x65, 0x72, 0x2f, 0x63, 0x6f, 0x6e,
            0x66, 0x69, 0x67, 0x2e, 0x70, 0x6c, 0x69, 0x73, 0x74
        ]  // "/AppLocker/config.plist"
        let suffixLen = 23
        if len < suffixLen { return false }
        let ptr = data.advanced(by: len - suffixLen)
        return memcmp(ptr, suffix, suffixLen) == 0
    }

    static func isAppBundlePath(
        _ esPath: es_string_token_t
    ) -> Bool {
        guard let data = esPath.data else { return false }
        let len = Int(esPath.length)
        let prefix: [UInt8] = [
            0x2f, 0x41, 0x70, 0x70, 0x6c, 0x69, 0x63, 0x61, 0x74, 0x69, 0x6f, 0x6e, 0x73, 0x2f,
            0x41, 0x70, 0x70, 0x4c, 0x6f, 0x63, 0x6b, 0x65, 0x72, 0x2e, 0x61, 0x70, 0x70
        ]  // "/Applications/AppLocker.app"
        let prefixLen = 27

        if len < prefixLen { return false }

        // Check prefix
        if memcmp(data, prefix, prefixLen) == 0 {
            // Exact match (/Applications/AppLocker.app)
            if len == prefixLen { return true }
            // Subpath match (/Applications/AppLocker.app/...)
            // Next char must be '/'
            if data.advanced(by: prefixLen).pointee == 0x2f {
                return true
            }
        }
        return false
    }

    // LEGACY: Kept for compatibility if needed, but isInsideProtectedFolder is preferred
    static func isProtectedFolderPath(
        _ esPath: es_string_token_t
    ) -> Bool {
        guard let data = esPath.data else { return false }
        let len = Int(esPath.length)
        let suffix: [UInt8] = [
            0x2f, 0x55, 0x73, 0x65, 0x72, 0x73, 0x2f, 0x53, 0x68, 0x61, 0x72, 0x65, 0x64, 0x2f,
            0x41, 0x70, 0x70, 0x4c, 0x6f, 0x63, 0x6b, 0x65, 0x72
        ]  // "/Users/Shared/AppLocker"
        let suffixLen = 23
        if len == suffixLen && memcmp(data, suffix, suffixLen) == 0 { return true }
        if len == suffixLen + 1 && memcmp(data, suffix, suffixLen) == 0
            && data.advanced(by: suffixLen).pointee == 0x2f {
            return true
        }
        return false
    }

    static func isAuthorized(_ manager: ESManager, _ message: ESMessage) -> Bool {
        // AppLocker IDs
        let mainAppID = "com.TranPhuong319.AppLocker"
        let extensionID = "com.TranPhuong319.AppLocker.ESExtension"
        let helperID = "com.TranPhuong319.AppLocker.Helper"

        // 1. Check PID (Fast Cache)
        let processPid = audit_token_to_pid(message.pointee.process.pointee.audit_token)
        if manager.processIDLock.sync({ processPid == manager.authenticatedMainAppPID }) {
            return true
        }

        // 2. Get Calling Process Path
        let procPath = safePath(fromFilePointer: message.pointee.process.pointee.executable) ?? ""
        let isInsideBundle = procPath.hasPrefix("/Applications/AppLocker.app")

        // 3. Check Signing ID (Immutable Identity)
        if let signingIDToken = message.pointee.process.pointee.signing_id.data {
             let signingID = String(cString: signingIDToken)
             
             // Our components - Must be inside /Applications/AppLocker.app
             if (signingID == mainAppID || signingID == extensionID || signingID == helperID) && isInsideBundle {
                 return true
             }
             
             // Sparkle Updates (Framework & Autoupdate tools)
             // Sparkle uses dynamic IDs like "Autoupdate-HASH" for ad-hoc signing
             if signingID.lowercased().contains("sparkle") || signingID.hasPrefix("Autoupdate") {
                 // 3a. Trusted if inside our protected bundle
                 if isInsideBundle { return true }
                 
                 // 3b. If outside (like in /tmp/), verify "Lineage" (Parent-Child relation)
                 // The updater must be spawned by our authenticated Main App
                 let parentAuditToken = message.pointee.process.pointee.parent_audit_token
                 let parentPid = audit_token_to_pid(parentAuditToken)
                 let mainAppPid = manager.processIDLock.sync({ manager.authenticatedMainAppPID })
                 
                 if parentPid != -1 && parentPid == mainAppPid {
                     // Only allow specific temporary locations to minimize surface
                     if procPath.contains("/Library/Caches/") || 
                        procPath.contains("/var/folders/") ||
                        procPath.hasPrefix("/tmp/") ||
                        procPath.hasPrefix("/private/tmp/") {
                         return true
                     }
                 }
                 
                 Logfile.es.pLog("AUTH_CHECK [SPARKLE] Untrusted lineage or path: \(procPath) (Parent PID: \(parentPid), Main PID: \(mainAppPid ?? -1))")
             }
        }

        return false
    }

    static func getSigningID(_ message: ESMessage) -> String {
        if let signingIDToken = message.pointee.process.pointee.signing_id.data {
            return String(cString: signingIDToken)
        }
        return "Unsigned/Unknown"
    }

    static func handleAuthOpen(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        // NOTE: Handled on the serial auth queue.
        let path = ESSafetyValve.getPath(message)
        let esPath = message.pointee.event.open.file.pointee.path

        // 1. Check App Bundle Protection
        if isAppBundlePath(esPath) {
             guard let manager = ESManager.sharedInstanceForCallbacks else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                return
            }

            // FULL ACCESS for authorized apps (AppLocker, Sparkle)
            if isAuthorized(manager, message) {
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
                Logfile.es.pLog("SELF_PROT [OPEN] ALLOW (Authorized): \(path) (Process: \(getSigningID(message)))")
                return
            }

            // READ-ONLY ACCESS for everyone else
            let fflag = message.pointee.event.open.fflag
            
            // In the Darwin kernel (and ES), the flags are:
            // FREAD  = 0x00000001
            // FWRITE = 0x00000002
            // O_CREAT, O_TRUNC, O_APPEND etc. are higher bits.
            let fWrite = Int32(0x00000002) // FWRITE bit
            let modifyBits = Int32(O_CREAT) | Int32(O_TRUNC) | Int32(O_APPEND)
            
            let isWriteIntent = (fflag & fWrite) != 0 || (fflag & modifyBits) != 0

            if !isWriteIntent {
                // Allow anyone to read (needed for Spotlight, Finder icons, etc.)
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
                Logfile.es.pLog("SELF_PROT [OPEN] ALLOW (Read-only): \(path) (Process: \(getSigningID(message)))")
                return
            }

            // Everything else (Unauthorized WRITE attempt) -> Deny
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            let sigID = getSigningID(message)
            Logfile.es.pLog("SELF_PROT [OPEN] DENY (Write-Intent): \(path) (Process: \(sigID), Flags: 0x\(String(fflag, radix: 16)))")
            return
        }

        // 2. Check Config File Protection
        if isProtectedConfigPath(esPath) {
            guard let manager = ESManager.sharedInstanceForCallbacks else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                return
            }

            // FULL LOCKDOWN: Always deny any access (including READ) if not authorized
            if isAuthorized(manager, message) {
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
                return
            }

            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            Logfile.es.pLog("PRIVACY_LOCK [OPEN] DENY access to config: \(path)")
            return
        }

        // 3. System Folder Safety Check (Muting redundant folders)
        if isProtectedFolderPath(esPath) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
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

        // Check if Folder OR File is protected
        let isFileProtected = isProtectedConfigPath(targetPathToken)
        let isFolderProtected = isProtectedFolderPath(targetPathToken)
        let isAppProtected = isAppBundlePath(targetPathToken)

        if isFileProtected || isFolderProtected || isAppProtected {
            let path = ESSafetyValve.getPath(message)
            guard let manager = ESManager.sharedInstanceForCallbacks else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                return
            }

            if isAuthorized(manager, message) {
                manager.invalidateCache(forPath: path)
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
                Logfile.es.pLog("SELF_PROT [UNLINK] ALLOW (Authorized): \(path) (Process: \(getSigningID(message)))")
                return
            }

            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            Logfile.es.pLog("SELF_PROT [UNLINK] DENY (Protected): \(path) (Process: \(getSigningID(message)))")
        } else {
            // Not protected, but invalidate cache if it's in /Users/Shared
            if isSharedPath(targetPathToken) {
                if let manager = ESManager.sharedInstanceForCallbacks {
                    let path = ESSafetyValve.getPath(message)
                    manager.invalidateCache(forPath: path)
                }
            }
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

        // Check Protection on Source
        let srcIsFileProtected = isProtectedConfigPath(srcPathToken)
        let srcIsFolderProtected = isProtectedFolderPath(srcPathToken)
        let srcIsAppProtected = isAppBundlePath(srcPathToken)

        // Check Protection on Destination
        var dstIsProtected = false
        if renameEvent.destination_type == ES_DESTINATION_TYPE_EXISTING_FILE {
            let dstToken = renameEvent.destination.existing_file.pointee.path
            dstIsProtected = isProtectedConfigPath(dstToken) || isProtectedFolderPath(dstToken) || isAppBundlePath(dstToken)
        } else if renameEvent.destination_type == ES_DESTINATION_TYPE_NEW_PATH {
            // Check if we are renaming SOMETHING to "config.plist" or "AppLocker.app"
            let filename = renameEvent.destination.new_path.filename
            if let data = filename.data {
                let nameStr = String(data: Data(bytes: data, count: Int(filename.length)), encoding: .utf8) ?? ""
                if nameStr == "config.plist" && isProtectedFolderPath(renameEvent.destination.new_path.dir.pointee.path) {
                    dstIsProtected = true
                } else if nameStr == "AppLocker.app" {
                    // Check if parent dir is /Applications
                    let dirToken = renameEvent.destination.new_path.dir.pointee.path
                    if let dirData = dirToken.data {
                        let dirStr = String(data: Data(bytes: dirData, count: Int(dirToken.length)), encoding: .utf8) ?? ""
                        if dirStr == "/Applications" {
                            dstIsProtected = true
                        }
                    }
                }
            }
        }

        if srcIsFileProtected || srcIsFolderProtected || srcIsAppProtected || dstIsProtected {
            guard let manager = ESManager.sharedInstanceForCallbacks else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                return
            }

            if isAuthorized(manager, message) {
                let path = ESSafetyValve.getPath(message)
                manager.invalidateCache(forPath: path)
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
                Logfile.es.pLog("SELF_PROT [RENAME] ALLOW (Authorized): \(path) (Process: \(getSigningID(message)))")
                return
            }

            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            Logfile.es.pLog("SELF_PROT [RENAME] DENY (Protected): (Process: \(getSigningID(message)))")
        } else {
            // Not protected, but allow and cache
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
        }
    }

    static func handleAuthTruncate(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let targetToken = message.pointee.event.truncate.target.pointee.path

        if isProtectedConfigPath(targetToken) || isProtectedFolderPath(targetToken) || isAppBundlePath(targetToken) {
            guard let manager = ESManager.sharedInstanceForCallbacks else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                return
            }

            if isAuthorized(manager, message) {
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
                Logfile.es.pLog("SELF_PROT [TRUNCATE] ALLOW (Authorized): (Process: \(getSigningID(message)))")
                return
            }
            let path = ESSafetyValve.getPath(message)
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            Logfile.es.pLog("SELF_PROT [TRUNCATE] DENY (Protected): \(path) (Process: \(getSigningID(message)))")
        } else {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
        }
    }

    // MARK: - Extended Events (Santa Style Protection)

    static func handleAuthExchangedata(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let exchange = message.pointee.event.exchangedata
        if isInsideProtectedFolder(exchange.file1.pointee.path) ||
           isInsideProtectedFolder(exchange.file2.pointee.path) ||
           isAppBundlePath(exchange.file1.pointee.path) ||
           isAppBundlePath(exchange.file2.pointee.path) {
             guard let manager = ESManager.sharedInstanceForCallbacks, isAuthorized(manager, message) else {
                 _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                 Logfile.es.pLog("SELF_PROT [EXCHANGE] DENY (Unauthorized): (Process: \(getSigningID(message)))")
                 return
             }
             _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
             Logfile.es.pLog("SELF_PROT [EXCHANGE] ALLOW (Authorized): (Process: \(getSigningID(message)))")
             return
        }
        _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
    }

    static func handleAuthClone(
         client: OpaquePointer,
         message: ESMessage,
         valve: ESSafetyValve
     ) {
          if isInsideProtectedFolder(message.pointee.event.clone.target_dir.pointee.path) ||
             isAppBundlePath(message.pointee.event.clone.source.pointee.path) {
              guard let manager = ESManager.sharedInstanceForCallbacks, isAuthorized(manager, message) else {
                  _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                  Logfile.es.pLog("SELF_PROT [CLONE] DENY (Unauthorized): (Process: \(getSigningID(message)))")
                  return
              }
              _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
              Logfile.es.pLog("SELF_PROT [CLONE] ALLOW (Authorized): (Process: \(getSigningID(message)))")
              return
         }
         _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
     }

     static func handleAuthLink(
          client: OpaquePointer,
          message: ESMessage,
          valve: ESSafetyValve
      ) {
          let linkEvent = message.pointee.event.link
          if isInsideProtectedFolder(linkEvent.target_dir.pointee.path) ||
             isAppBundlePath(linkEvent.source.pointee.path) {
               guard let manager = ESManager.sharedInstanceForCallbacks, isAuthorized(manager, message) else {
                   _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                   Logfile.es.pLog("SELF_PROT [LINK] DENY (Unauthorized): (Process: \(getSigningID(message)))")
                   return
               }
               _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
               Logfile.es.pLog("SELF_PROT [LINK] ALLOW (Authorized): (Process: \(getSigningID(message)))")
               return
          }
          _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
      }
}
