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

final class ConfigStore {
    static let shared = ConfigStore()
    let configURL = URL(fileURLWithPath: "/Users/Shared/AppLocker/config.plist")

    private init() {
        let directory = configURL.deletingLastPathComponent()
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: attributes
        )
    }

    func performHandshake(completion: @escaping (Bool) -> Void) {
        let currentProcessID = getpid()
        ESXPCClient.shared.allowConfigAccess(currentProcessID) { success in
            completion(success)
        }
    }

    func load() -> ConfigLoadResult {
        var result: [String: LockedAppConfig] = [:]
        var isDisabled = false
        var isLegacyFormat = false

        guard FileManager.default.fileExists(atPath: configURL.path),
              let plistData = try? Data(contentsOf: configURL, options: .mappedIfSafe) else {
            return ConfigLoadResult(apps: result, isDisabled: isDisabled, isLegacyFormat: isLegacyFormat)
        }

        let decoder = PropertyListDecoder()
        let uid = String(getuid())
        if let userConfigMap = try? decoder.decode([String: UserConfig].self, from: plistData),
           let config = userConfigMap[uid] {
            for app in config.apps {
                result[app.path] = app
            }
            isDisabled = config.isDisabled
        } else if let userBlockedAppsMap = try? decoder.decode([String: [LockedAppConfig]].self, from: plistData),
           let apps = userBlockedAppsMap[uid] {
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
            let userID = String(getuid())
            var fullConfig: [String: UserConfig] = [:]

            // 1. Read existing config to avoid overwriting other users
            if FileManager.default.fileExists(atPath: configURL.path),
               let existingData = try? Data(contentsOf: configURL) {
                let decoder = PropertyListDecoder()
                if let decoded = try? decoder.decode([String: UserConfig].self, from: existingData) {
                    fullConfig = decoded
                } else if let oldFormat = try? decoder.decode([String: [LockedAppConfig]].self, from: existingData) {
                    for (key, apps) in oldFormat {
                        fullConfig[key] = UserConfig(isDisabled: false, apps: apps)
                    }
                }
            }

            // 2. Update current user's rules
            fullConfig[userID] = UserConfig(isDisabled: isDisabled, apps: Array(map.values))

            // 3. Encode and save
            let plistData = try encoder.encode(fullConfig)
            try plistData.write(to: configURL, options: .atomic)

            // 4. Set permissions to 0o666 for multi-user access
            var attributes = [FileAttributeKey: Any]()
            attributes[.posixPermissions] = 0o666
            try? FileManager.default.setAttributes(attributes, ofItemAtPath: configURL.path)

            Logfile.core.debug(
                "ConfigStore.save ES: updated \(map.count) apps for uid \(userID). Total users: \(fullConfig.count)"
            )
        } catch {
            Logfile.core.error("ConfigStore.save failed: \(error.localizedDescription)")
        }
    }
}
