//
//  CDHashHelper.swift
//  AppLocker
//
//  Created by Doe Phương on 1/8/26.
//

import Foundation
import Security

/// Extract cdhash (Code Directory Hash) of a signed binary/bundle on disk in <1ms without reading full binary data.
public func extractCDHash(forPath path: String) -> String? {
    let url = URL(fileURLWithPath: path)
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
          let code = staticCode else { return nil }
    
    var dictionary: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &dictionary) == errSecSuccess,
          let info = dictionary as? [String: Any],
          let cdhashes = info[kSecCodeInfoCdHashes as String] as? [Data],
          let primaryCDHash = cdhashes.first else {
        return nil
    }
    return primaryCDHash.map { String(format: "%02x", $0) }.joined()
}

