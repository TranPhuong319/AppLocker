//
//  ESEventAuthFile.swift
//  ESExtension
//
//  Created by Doe Phương on 17/1/26.
//

import EndpointSecurity
import Foundation
import os

extension ESManager {


    static func isSharedPath(_ esPath: es_string_token_t) -> Bool {
        guard let data = esPath.data else { return false }
        let len = Int(esPath.length)
        // "/Users/Shared" is 13 chars
        let prefixLen = 13
        if len < prefixLen { return false }

        let prefix: [UInt8] = [
            0x2f, 0x55, 0x73, 0x65, 0x72, 0x73, 0x2f, 0x53, 0x68, 0x61, 0x72, 0x65, 0x64,
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
            0x41, 0x70, 0x70, 0x4c, 0x6f, 0x63, 0x6b, 0x65, 0x72,
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
            0x66, 0x69, 0x67, 0x2e, 0x70, 0x6c, 0x69, 0x73, 0x74,
        ]  // "/AppLocker/config.plist"
        let suffixLen = 23
        if len < suffixLen { return false }
        let ptr = data.advanced(by: len - suffixLen)
        return memcmp(ptr, suffix, suffixLen) == 0
    }

    // LEGACY: Kept for compatibility if needed, but isInsideProtectedFolder is preferred
    static func isProtectedFolderPath(
        _ esPath: es_string_token_t
    ) -> Bool {
        guard let data = esPath.data else { return false }
        let len = Int(esPath.length)
        let suffix: [UInt8] = [
            0x2f, 0x55, 0x73, 0x65, 0x72, 0x73, 0x2f, 0x53, 0x68, 0x61, 0x72, 0x65, 0x64, 0x2f,
            0x41, 0x70, 0x70, 0x4c, 0x6f, 0x63, 0x6b, 0x65, 0x72,
        ]  // "/Users/Shared/AppLocker"
        let suffixLen = 23
        if len == suffixLen && memcmp(data, suffix, suffixLen) == 0 { return true }
        if len == suffixLen + 1 && memcmp(data, suffix, suffixLen) == 0
            && data.advanced(by: suffixLen).pointee == 0x2f
        {
            return true
        }
        return false
    }

    /// Advanced Identity Check (Santa-Style):
    /// Identifies processes based on cryptographical Signing IDs.
    static func isAuthorized(_ manager: ESManager, _ message: ESMessage) -> Bool {
        // AppLocker IDs
        let mainAppID = "com.TranPhuong319.AppLocker"
        let extensionID = "com.TranPhuong319.AppLocker.ESExtension"

        // 1. Check PID (Fast Cache)
        let processPid = audit_token_to_pid(message.pointee.process.pointee.audit_token)
        if manager.processIDLock.sync({ processPid == manager.authenticatedMainAppPID }) {
            return true
        }

        // 2. Check Signing ID (Immutable Identity)
        if let signingIDToken = message.pointee.process.pointee.signing_id.data {
             let signingID = String(cString: signingIDToken)
             if signingID == mainAppID || signingID == extensionID {
                 return true
             }
        }
        
        return false
    }

    static func handleAuthOpen(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        // NOTE: Handled on the serial auth queue.
        let path = ESSafetyValve.getPath(message)
        let esPath = message.pointee.event.open.file.pointee.path

        // Double check for safety
        if isProtectedFolderPath(esPath) {
            _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            return
        }

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

        if isFileProtected || isFolderProtected {
            let path = ESSafetyValve.getPath(message)
            guard let manager = ESManager.sharedInstanceForCallbacks else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                return
            }

            if isAuthorized(manager, message) {
                manager.invalidateCache(forPath: path)
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
                Logfile.es.log("RESP_FAST [UNLINK] ALLOW (AuthPID): \(path)")
                return
            }

            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            Logfile.es.log("RESP_FAST [UNLINK] DENY (Protected): \(path)")
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

        // Check Protection on Destination
        var dstIsProtected = false
        if renameEvent.destination_type == ES_DESTINATION_TYPE_EXISTING_FILE {
            let dstToken = renameEvent.destination.existing_file.pointee.path
            dstIsProtected = isProtectedConfigPath(dstToken) || isProtectedFolderPath(dstToken)
        } else if renameEvent.destination_type == ES_DESTINATION_TYPE_NEW_PATH {
            // Check if we are renaming SOMETHING to "config.plist" in the AppLocker folder
            let filename = renameEvent.destination.new_path.filename
            if filename.length == 12, let data = filename.data {
                let cfgName: [UInt8] = [
                    0x63, 0x6f, 0x6e, 0x66, 0x69, 0x67, 0x2e, 0x70, 0x6c, 0x69, 0x73, 0x74,
                ]
                if memcmp(data, cfgName, 12) == 0 {
                    // Check if parent dir is /Users/Shared/AppLocker
                    if isProtectedFolderPath(renameEvent.destination.new_path.dir.pointee.path) {
                        dstIsProtected = true
                    }
                }
            }
        }

        if srcIsFileProtected || srcIsFolderProtected || dstIsProtected {
            guard let manager = ESManager.sharedInstanceForCallbacks else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                return
            }

            if isAuthorized(manager, message) {
                let path = ESSafetyValve.getPath(message)
                manager.invalidateCache(forPath: path)
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
                Logfile.es.log("RESP_FAST [RENAME] ALLOW (AuthPID)")
                return
            }

            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            Logfile.es.log("RESP_FAST [RENAME] DENY (Protected)")
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

        if isProtectedConfigPath(targetToken) || isProtectedFolderPath(targetToken) {
            guard let manager = ESManager.sharedInstanceForCallbacks else {
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                return
            }

            if isAuthorized(manager, message) {
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: false)
                Logfile.es.log("RESP_FAST [TRUNCATE] ALLOW (AuthPID)")
                return
            }
            let path = ESSafetyValve.getPath(message)
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            Logfile.es.log("SELF_PROT [TRUNCATE] DENY (Protected): \(path)")
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
           isInsideProtectedFolder(exchange.file2.pointee.path) {
             guard let manager = ESManager.sharedInstanceForCallbacks, isAuthorized(manager, message) else {
                 _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                 Logfile.es.log("SELF_PROT [EXCHANGE] DENY (Unauthorized Identity)")
                 return
             }
        }
        _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
    }

    static func handleAuthClone(
         client: OpaquePointer,
         message: ESMessage,
         valve: ESSafetyValve
     ) {
         if isInsideProtectedFolder(message.pointee.event.clone.target_dir.pointee.path) {
              guard let manager = ESManager.sharedInstanceForCallbacks, isAuthorized(manager, message) else {
                  _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                  Logfile.es.log("SELF_PROT [CLONE] DENY (Unauthorized Identity)")
                  return
              }
         }
         _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
     }

     static func handleAuthLink(
          client: OpaquePointer,
          message: ESMessage,
          valve: ESSafetyValve
      ) {
          if isInsideProtectedFolder(message.pointee.event.link.target_dir.pointee.path) {
               guard let manager = ESManager.sharedInstanceForCallbacks, isAuthorized(manager, message) else {
                   _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                   Logfile.es.log("SELF_PROT [LINK] DENY (Unauthorized Identity)")
                   return
               }
          }
          _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
      }
}
