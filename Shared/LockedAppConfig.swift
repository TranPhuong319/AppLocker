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
    var sha256: String?
    var execFile: String?
    var name: String?
    var cdhash: String?

    enum CodingKeys: String, CodingKey {
        case bundleID, path, sha256, execFile, name, cdhash
    }

    /// Convenience initializer for mock data in Previews
    static func mock(for app: InstalledApp) -> LockedAppConfig {
        LockedAppConfig(
            bundleID: app.bundleID,
            path: app.path,
            sha256: nil,
            execFile: app.name,
            name: app.name,
            cdhash: "mock_cdhash_hash"
        )
    }
}

extension LockedAppConfig {
    func toDict() -> [String: String] {
        var dict = ["bundleID": bundleID, "path": path]
        if let cdhash = cdhash { dict["cdhash"] = cdhash }
        if let sha256 = sha256 { dict["sha256"] = sha256 }
        return dict
    }
}

struct UserConfig: Codable {
    var isDisabled: Bool
    var apps: [LockedAppConfig]
}
