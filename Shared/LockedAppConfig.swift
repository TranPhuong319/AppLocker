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

    /// Convenience initializer for mock data in Previews
    static func mock(for app: InstalledApp) -> LockedAppConfig {
        LockedAppConfig(
            bundleID: app.bundleID,
            path: app.path,
            sha256: "mock_sha256_hash",
            blockMode: "Launcher",
            execFile: app.name,
            name: app.name
        )
    }
}

extension LockedAppConfig {
    func toDict() -> [String: String] {
        return ["bundleID": bundleID, "path": path, "sha256": sha256]
    }
}
