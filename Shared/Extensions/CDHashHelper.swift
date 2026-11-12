//
//  CDHashHelper.swift
//  AppLocker
//
//  Created by Doe Phương on 1/8/26.
//

import Foundation
import Security

// MARK: - Data Hex Encoding

extension Data {
    public var hexEncodedString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - URL App Bundle Resolution

extension URL {
    /// Returns the enclosing .app bundle URL if this URL is inside an application bundle, or self otherwise.
    public var enclosingAppBundleURL: URL {
        var current = self
        while current.pathComponents.count > 1 {
            if current.pathExtension.lowercased() == "app" {
                return current
            }
            current.deleteLastPathComponent()
        }
        return self
    }
}

/// Extract cdhash (Code Directory Hash) of a signed binary/bundle on disk in <1ms without reading full binary data.
public func cdHash(for path: String) -> String? {
    let url = URL(fileURLWithPath: path)
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
          let code = staticCode else { return nil }

    var dictionary: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopySigningInformation(code, flags, &dictionary) == errSecSuccess,
          let info = dictionary as? [String: Any],
          let cdhashes = info[kSecCodeInfoCdHashes as String] as? [Data],
          let primaryCDHash = cdhashes.first else {
        return nil
    }
    return primaryCDHash.hexEncodedString
}
