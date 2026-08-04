//
//  PathUtils.swift
//  ESExtension
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import EndpointSecurity

// Safely extract string from es_string_token_t structure (not guaranteed to be null-terminated).
func string(from token: es_string_token_t) -> String? {
    guard let dataPtr = token.data, token.length > 0 else { return nil }
    let rawPtr = UnsafeRawPointer(dataPtr).assumingMemoryBound(to: UInt8.self)
    let buffer = UnsafeBufferPointer(start: rawPtr, count: Int(token.length))
    return String(bytes: buffer, encoding: .utf8)
}

// Safely extract path from es_file_t pointer.
func safePath(fromFilePointer filePtr: UnsafePointer<es_file_t>?) -> String? {
    guard let filePtr = filePtr else { return nil }
    return string(from: filePtr.pointee.path)
}


extension ESManager {
    // Compute app bundle name for an exec path (best-effort).
    func computeAppName(forExecPath path: String) -> String {
        var url = URL(fileURLWithPath: path)
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" {
                if let bundle = Bundle(url: url) {
                    let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    if let name = displayName ?? bundleName {
                        return name
                    }
                }
                return url.deletingPathExtension().lastPathComponent
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    // MARK: - Protected Paths & Verification

    private static func matchTokenPrefix(_ token: es_string_token_t, prefix: String) -> Bool {
        guard let data = token.data else { return false }
        let prefixBytes = Array(prefix.utf8)
        let len = Int(token.length)
        guard len >= prefixBytes.count else { return false }

        if memcmp(data, prefixBytes, prefixBytes.count) == 0 {
            if len == prefixBytes.count { return true }
            return data.advanced(by: prefixBytes.count).pointee == 0x2f // '/'
        }
        return false
    }

    static func isSharedPath(_ esPath: es_string_token_t) -> Bool {
        return matchTokenPrefix(esPath, prefix: "/Users/Shared")
    }

    /// Checks if path IS or IS INSIDE /Users/Shared/AppLocker
    static func isInsideProtectedFolder(_ esPath: es_string_token_t) -> Bool {
        return matchTokenPrefix(esPath, prefix: "/Users/Shared/AppLocker")
    }

    static func isProtectedConfigPath(_ esPath: es_string_token_t) -> Bool {
        guard let data = esPath.data else { return false }
        let len = Int(esPath.length)
        let suffixBytes = Array("/AppLocker/config.plist".utf8)
        guard len >= suffixBytes.count else { return false }
        let ptr = data.advanced(by: len - suffixBytes.count)
        return memcmp(ptr, suffixBytes, suffixBytes.count) == 0
    }

    static func isAppBundlePath(_ esPath: es_string_token_t) -> Bool {
        return matchTokenPrefix(esPath, prefix: "/Applications/AppLocker.app")
    }

    static func isProtectedFolderPath(_ esPath: es_string_token_t) -> Bool {
        return matchTokenPrefix(esPath, prefix: "/Users/Shared/AppLocker")
    }
}
