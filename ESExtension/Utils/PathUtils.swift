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
    let str = String(decoding: buffer, as: UTF8.self)

    // Trả về copy hoàn chỉnh (String ở Swift đã copy-on-write), an toàn để dùng async.
    return str
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
