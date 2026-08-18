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
                let bundle = Bundle(url: url)
                let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                return name ?? url.deletingPathExtension().lastPathComponent
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    // MARK: - Protected Paths & Verification

    /// Checks if path IS or IS INSIDE /Users/Shared/AppLocker
    static func isInsideProtectedFolder(_ esPath: es_string_token_t) -> Bool {
        guard let path = string(from: esPath) else { return false }
        return path == "/Users/Shared/AppLocker" || path.hasPrefix("/Users/Shared/AppLocker/")
    }

    static func isProtectedConfigPath(_ esPath: es_string_token_t) -> Bool {
        guard let path = string(from: esPath) else { return false }
        return path.hasSuffix("/AppLocker/config.plist")
    }

    static func isAppBundlePath(_ esPath: es_string_token_t) -> Bool {
        guard let path = string(from: esPath) else { return false }
        return path == "/Applications/AppLocker.app" || path.hasPrefix("/Applications/AppLocker.app/")
    }
}
