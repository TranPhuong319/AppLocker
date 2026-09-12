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

struct UserConfig: Codable, Sendable {
    var isDisabled: Bool
    var apps: [LockedAppConfig]
    var allowIncomingCalls: Bool?
    var autoLockTimeoutMinutes: Int?

    init(
        isDisabled: Bool,
        apps: [LockedAppConfig],
        allowIncomingCalls: Bool? = nil,
        autoLockTimeoutMinutes: Int? = nil
    ) {
        self.isDisabled = isDisabled
        self.apps = apps
        self.allowIncomingCalls = allowIncomingCalls
        self.autoLockTimeoutMinutes = autoLockTimeoutMinutes
    }
}

extension UserConfig {
    static let baseDirectoryURL = URL(fileURLWithPath: "/Users/Shared/AppLocker")

    static func configURL(for uid: uid_t) -> URL {
        baseDirectoryURL
            .appendingPathComponent(String(uid), isDirectory: true)
            .appendingPathComponent("config.plist")
    }

    static func load(for uid: uid_t) -> UserConfig? {
        let fileURL = configURL(for: uid)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            return nil
        }
        return try? PropertyListDecoder().decode(UserConfig.self, from: data)
    }

    static func loadAll() -> [uid_t: UserConfig] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: baseDirectoryURL.path) else {
            return [:]
        }
        var result: [uid_t: UserConfig] = [:]
        for item in items {
            guard let uid = uid_t(item),
                  let config = load(for: uid) else { continue }
            result[uid] = config
        }
        return result
    }
}
