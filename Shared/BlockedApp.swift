//
//  BlockedApp.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//


import Foundation
import CryptoKit

struct BlockedApp: Codable, Identifiable {
    var id = UUID()
    let bundleID: String
    let path: String       // full path to executable
    let sha256: String
}

extension BlockedApp {
    func toDict() -> [String: String] {
        return ["bundleID": bundleID, "path": path, "sha256": sha256]
    }
}

// Tính SHA256
extension URL {
    func sha256() -> String? {
        guard let data = try? Data(contentsOf: self) else { return nil }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
