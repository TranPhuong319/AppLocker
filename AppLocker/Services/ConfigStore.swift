//
//  ConfigStore.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation

final class ConfigStore {
    static let shared = ConfigStore()
    private init() {}

    var configURL: URL {
        let configDirectory = URL(
            fileURLWithPath: "/Users/Shared/AppLocker",
            isDirectory: true
        )
        try? ensureDirectoryExists(configDirectory)
        return configDirectory.appendingPathComponent("config.plist")
    }

    private func ensureDirectoryExists(_ directory: URL) throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [
                    .posixPermissions: 0o755
                ]
            )
        }
    }

    func performHandshake(completion: @escaping (Bool) -> Void) {
        let currentProcessID = getpid()
        ESXPCClient.shared.allowConfigAccess(currentProcessID) { success in
            completion(success)
        }
    }

    func load() -> (apps: [String: LockedAppConfig], isDisabled: Bool) {
        var result: [String: LockedAppConfig] = [:]
        var isDisabled = false

        guard FileManager.default.fileExists(atPath: configURL.path),
              let plistData = try? Data(contentsOf: configURL, options: .mappedIfSafe) else {
            return (result, isDisabled)
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
            for app in apps {
                result[app.path] = app
            }
        }

        return (result, isDisabled)
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
            
            Logfile.core.debug("ConfigStore.save ES: updated \(map.count) apps for uid \(userID). Total users: \(fullConfig.count)")
        } catch {
            Logfile.core.error("ConfigStore.save failed: \(error.localizedDescription)")
        }
    }
}
