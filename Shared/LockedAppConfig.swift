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

    var isHidden: Bool?

    enum CodingKeys: String, CodingKey {
        case bundleID, path, sha256, execFile, name, cdhash, isHidden
    }

    init(
        bundleID: String,
        path: String,
        sha256: String? = nil,
        execFile: String? = nil,
        name: String? = nil,
        cdhash: String? = nil,
        isHidden: Bool? = false
    ) {
        self.bundleID = bundleID
        self.path = path
        self.sha256 = sha256
        self.execFile = execFile
        self.name = name
        self.cdhash = cdhash
        self.isHidden = isHidden
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bundleID = try container.decode(String.self, forKey: .bundleID)
        self.path = try container.decode(String.self, forKey: .path)
        self.sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        self.execFile = try container.decodeIfPresent(String.self, forKey: .execFile)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.cdhash = try container.decodeIfPresent(String.self, forKey: .cdhash)
        self.isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }

    /// Convenience initializer for mock data in Previews
    static func mock(for app: InstalledApp) -> LockedAppConfig {
        LockedAppConfig(
            bundleID: app.bundleID,
            path: app.path,
            sha256: nil,
            execFile: app.name,
            name: app.name,
            cdhash: "mock_cdhash_hash",
            isHidden: false
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
