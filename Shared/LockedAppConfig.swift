//
//  LockedAppConfig.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation
import OSLog

struct LockedAppConfig: Codable, Hashable, Sendable {
    let bundleID: String
    let path: String
    var execFile: String?
    var name: String?
    var cdhash: String?

    var isHidden: Bool?

    init(
        bundleID: String,
        path: String,
        execFile: String? = nil,
        name: String? = nil,
        cdhash: String? = nil,
        isHidden: Bool? = false
    ) {
        self.bundleID = bundleID
        self.path = path
        self.execFile = execFile
        self.name = name
        self.cdhash = cdhash
        self.isHidden = isHidden
    }

    #if DEBUG
    /// Convenience initializer for mock data in Previews
    static func mock(for app: InstalledApp) -> LockedAppConfig {
        LockedAppConfig(
            bundleID: app.bundleID,
            path: app.path,
            execFile: app.name,
            name: app.name,
            cdhash: "mock_cdhash_hash",
            isHidden: false
        )
    }
    #endif
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

    static func configURL(for uid: uid_t, baseDirectoryURL: URL = UserConfig.baseDirectoryURL) -> URL {
        baseDirectoryURL
            .appendingPathComponent(String(uid), isDirectory: true)
            .appendingPathComponent("config.plist")
    }

    static func load(for uid: uid_t, baseDirectoryURL: URL = UserConfig.baseDirectoryURL) -> UserConfig? {
        let fileURL = configURL(for: uid, baseDirectoryURL: baseDirectoryURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let decoder = PropertyListDecoder()
            if let config = try? decoder.decode(UserConfig.self, from: data) {
                return config
            }
            if let apps = try? decoder.decode([LockedAppConfig].self, from: data) {
                return UserConfig(isDisabled: false, apps: apps)
            }
            return nil
        } catch {
            Logfile.policy.error(
                """
                [Config] Failed to load config for UID \(uid, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """
            )
            return nil
        }
    }

    static func loadAll(baseDirectoryURL: URL = UserConfig.baseDirectoryURL) -> [uid_t: UserConfig] {
        let items: [String]
        do {
            items = try FileManager.default.contentsOfDirectory(atPath: baseDirectoryURL.path)
        } catch {
            Logfile.policy.error(
                "[Config] Failed to list base directory: \(error.localizedDescription, privacy: .public)"
            )
            return [:]
        }
        var result: [uid_t: UserConfig] = [:]
        for item in items {
            guard let uid = uid_t(item),
                  let config = load(for: uid, baseDirectoryURL: baseDirectoryURL) else { continue }
            result[uid] = config
        }
        return result
    }
}
