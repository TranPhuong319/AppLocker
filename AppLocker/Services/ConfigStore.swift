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
        switch modeLock {
        case .launcher:
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            let configDirectory = appSupport.appendingPathComponent("AppLocker", isDirectory: true)
            try? ensureDirectoryExists(configDirectory)
            return configDirectory.appendingPathComponent("config.plist")

        case .esMode:
            let configDirectory = URL(
                fileURLWithPath: "/Users/Shared/AppLocker",
                isDirectory: true
            )
            try? ensureDirectoryExists(configDirectory)
            return configDirectory.appendingPathComponent("config.plist")

        case .none:
            fatalError()
        }
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

    private func shouldRequestES() -> Bool {
        return modeLock != AppMode.launcher
    }

    func performHandshake(completion: @escaping (Bool) -> Void) {
        guard shouldRequestES() else {
            completion(true) // skip request nếu Launcher
            return
        }
        let currentProcessID = getpid()
        ESXPCClient.shared.allowConfigAccess(currentProcessID) { success in
            completion(success)
        }
    }

    func load() -> (apps: [String: LockedAppConfig], isDisabled: Bool) {
        var result: [String: LockedAppConfig] = [:]
        var isDisabled = false

        // NOTE: Handshake is already done by LockES.bootstrap() BEFORE calling load().
        // DO NOT call requestAccessIfNeeded here to avoid double XPC calls and timeouts.

        guard FileManager.default.fileExists(atPath: configURL.path),
              let plistData = try? Data(contentsOf: configURL, options: .mappedIfSafe) else {
            return (result, isDisabled)
        }

        let decoder = PropertyListDecoder()

        switch modeLock {
        case .launcher:
            if let userConfigMap = try? decoder.decode([String: UserConfig].self, from: plistData),
               let config = userConfigMap["Launcher"] {
                for item in config.apps {
                    result[item.path] = item
                }
                isDisabled = config.isDisabled
            } else if let container = try? decoder.decode([String: [LockedAppConfig]].self, from: plistData),
               let blockedAppsList = container["BlockedApps"] {
                for item in blockedAppsList {
                    result[item.path] = item
                }
            } else if let blockedAppsList = try? decoder.decode([LockedAppConfig].self, from: plistData) {
                for item in blockedAppsList {
                    result[item.path] = item
                }
            }

        case .esMode:
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

        case .none:
            break
        }

        return (result, isDisabled)
    }

    func save(apps map: [String: LockedAppConfig], isDisabled: Bool) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        do {
            switch modeLock {
            case .launcher:
                let blockedAppsList = Array(map.values)
                let userConfig = UserConfig(isDisabled: isDisabled, apps: blockedAppsList)
                let configDictionary: [String: UserConfig] = ["Launcher": userConfig]
                let plistData = try encoder.encode(configDictionary)
                try plistData.write(to: configURL, options: .atomic)
                Logfile.core.debug("ConfigStore.save launcher: wrote \(blockedAppsList.count) apps")

            case .esMode:
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

            case .none:
                return
            }
        } catch {
            Logfile.core.error("ConfigStore.save failed: \(error.localizedDescription)")
        }
    }

}
