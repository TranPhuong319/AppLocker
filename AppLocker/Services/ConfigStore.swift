//
//  ConfigStore.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation

struct ConfigLoadResult {
    let apps: [String: LockedAppConfig]
    let isDisabled: Bool
    let isLegacyFormat: Bool
}

final class ConfigStore: Sendable {
    static let shared = ConfigStore()
    static let baseDirectoryURL = URL(fileURLWithPath: "/Users/Shared/AppLocker")
    static let legacyConfigURL = URL(fileURLWithPath: "/Users/Shared/AppLocker/config.plist")

    var userDirectoryURL: URL {
        Self.baseDirectoryURL.appendingPathComponent(String(getuid()), isDirectory: true)
    }

    var configURL: URL {
        userDirectoryURL.appendingPathComponent("config.plist")
    }

    private init() {
        ensureDirectoryExists(Self.baseDirectoryURL)
        ensureDirectoryExists(userDirectoryURL)
    }

    private func ensureDirectoryExists(_ url: URL) {
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: attributes
        )
    }

    func performHandshake(completion: @escaping @Sendable (Bool) -> Void) {
        let currentProcessID = getpid()
        ESXPCClient.shared.allowConfigAccess(currentProcessID) { success in
            completion(success)
        }
    }

    func load() -> ConfigLoadResult {
        migrateLegacyConfigIfNeeded()

        var result: [String: LockedAppConfig] = [:]
        var isDisabled = false
        var isLegacyFormat = false

        guard FileManager.default.fileExists(atPath: configURL.path),
              let plistData = try? Data(contentsOf: configURL, options: .mappedIfSafe) else {
            return ConfigLoadResult(apps: result, isDisabled: isDisabled, isLegacyFormat: isLegacyFormat)
        }

        let decoder = PropertyListDecoder()
        if let config = try? decoder.decode(UserConfig.self, from: plistData) {
            for app in config.apps {
                result[app.path] = app
            }
            isDisabled = config.isDisabled
        } else if let apps = try? decoder.decode([LockedAppConfig].self, from: plistData) {
            isLegacyFormat = true
            for app in apps {
                result[app.path] = app
            }
        }

        return ConfigLoadResult(apps: result, isDisabled: isDisabled, isLegacyFormat: isLegacyFormat)
    }

    func save(apps map: [String: LockedAppConfig], isDisabled: Bool) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        do {
            ensureDirectoryExists(userDirectoryURL)

            let userConfig = UserConfig(isDisabled: isDisabled, apps: Array(map.values))
            let plistData = try encoder.encode(userConfig)
            try plistData.write(to: configURL, options: .atomic)

            var attributes = [FileAttributeKey: Any]()
            attributes[.posixPermissions] = 0o666
            try? FileManager.default.setAttributes(attributes, ofItemAtPath: configURL.path)

            Logfile.policy.debug(
                """
                [ConfigStore] Saved \(map.count, privacy: .public) apps for uid \
                \(getuid(), privacy: .public) at \(self.configURL.path, privacy: .public)
                """
            )
        } catch {
            Logfile.policy.error("[ConfigStore] Save failed: \(error.localizedDescription)")
        }
    }

    private func migrateLegacyConfigIfNeeded() {
        let legacyPath = Self.legacyConfigURL.path
        guard FileManager.default.fileExists(atPath: legacyPath),
              let legacyData = try? Data(contentsOf: Self.legacyConfigURL) else {
            return
        }

        let decoder = PropertyListDecoder()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        var configsToMigrate: [String: UserConfig] = [:]
        if let fullConfig = try? decoder.decode([String: UserConfig].self, from: legacyData) {
            configsToMigrate = fullConfig
        } else if let oldFormat = try? decoder.decode([String: [LockedAppConfig]].self, from: legacyData) {
            for (key, apps) in oldFormat {
                configsToMigrate[key] = UserConfig(isDisabled: false, apps: apps)
            }
        }

        guard !configsToMigrate.isEmpty else { return }

        var allSucceeded = true
        for (uidString, userConfig) in configsToMigrate {
            let targetDir = Self.baseDirectoryURL.appendingPathComponent(uidString, isDirectory: true)
            ensureDirectoryExists(targetDir)
            let targetURL = targetDir.appendingPathComponent("config.plist")

            do {
                let data = try encoder.encode(userConfig)
                try data.write(to: targetURL, options: .atomic)
                var attributes = [FileAttributeKey: Any]()
                attributes[.posixPermissions] = 0o666
                try? FileManager.default.setAttributes(attributes, ofItemAtPath: targetURL.path)
            } catch {
                allSucceeded = false
                Logfile.policy.error(
                    """
                    [ConfigStore] Migration failed for uid \(uidString, privacy: .public): \
                    \(error.localizedDescription)
                    """
                )
            }
        }

        if allSucceeded {
            try? FileManager.default.removeItem(at: Self.legacyConfigURL)
            Logfile.policy.info(
                """
                [ConfigStore] Legacy config successfully migrated to \
                \(configsToMigrate.count, privacy: .public) user directories and deleted.
                """
            )
        }
    }
}
