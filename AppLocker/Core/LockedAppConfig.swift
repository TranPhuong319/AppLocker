//
//  LockedAppConfig.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation

struct LockedAppConfig: Codable, Hashable {
    let bundleID: String
    let path: String
    var sha256: String
    let blockMode: String
    let execFile: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case bundleID, path, sha256, blockMode, execFile, name
    }
}

extension LockedAppConfig {
    // EN: Convert to a simple dictionary for XPC transfer.
    // VI: Chuyển sang dictionary đơn giản để truyền qua XPC.
    func toDict() -> [String: String] {
        return ["bundleID": bundleID, "path": path, "sha256": sha256]
    }
}
