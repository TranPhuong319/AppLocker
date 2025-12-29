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
    if let cstr = file.path.data {
        return String(cString: cstr)
    }
    return nil
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
