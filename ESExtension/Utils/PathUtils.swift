//
//  PathUtils.swift
//  ESExtension
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import EndpointSecurity

// Safely extract path from es_file_t pointer.
func safePath(fromFilePointer filePtr: UnsafePointer<es_file_t>?) -> String? {
    guard let filePtr = filePtr else { return nil }
    let file = filePtr.pointee
    let token = file.path
    guard let dataPtr = token.data else { return nil }
    let length = Int(token.length)

    // Tạo String bằng cách decode từ buffer với length (không phụ thuộc null-terminator).
    let rawPtr = UnsafeRawPointer(dataPtr).assumingMemoryBound(to: UInt8.self)
    let buffer = UnsafeBufferPointer(start: rawPtr, count: length)
    return String(bytes: buffer, encoding: .utf8)
}

extension ESManager {
    // Compute app bundle name for an exec path (best-effort).
    func computeAppName(forExecPath path: String) -> String {
        let execFile = URL(fileURLWithPath: path)
        let appBundleURL = execFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var appName = appBundleURL.deletingPathExtension().lastPathComponent
        if let bundle = Bundle(url: appBundleURL) {
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                appName = displayName
            } else if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                appName = name
            }
        }
        return appName
    }
}
//
//  ESManager+ProtectedPaths.swift
//  ESExtension
//
//  Created by Doe Phương on 30/1/26.
//

import EndpointSecurity
import Foundation

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
}
