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

        case .es:
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

    func load() -> [String: LockedAppConfig] {
        var result: [String: LockedAppConfig] = [:]

        // NOTE: Handshake is already done by LockES.bootstrap() BEFORE calling load().
        // DO NOT call requestAccessIfNeeded here to avoid double XPC calls and timeouts.

        guard FileManager.default.fileExists(atPath: configURL.path),
              let plistData = try? Data(contentsOf: configURL) else {
            return [:]
        }

        let decoder = PropertyListDecoder()

        switch modeLock {
        case .launcher:
            if let container = try? decoder.decode(
                [String: [LockedAppConfig]].self,
                from: plistData
            ),
               let blockedAppsList = container["BlockedApps"] {
                for item in blockedAppsList {
                    result[item.path] = item
                }
            } else if let blockedAppsList = try? decoder.decode(
                [LockedAppConfig].self,
                from: plistData
            ) {
                for item in blockedAppsList {
                    result[item.path] = item
                }
            }

        case .es:
            let uid = String(getuid())
            if let userBlockedAppsMap = try? decoder.decode([String: [LockedAppConfig]].self, from: plistData),
               let apps = userBlockedAppsMap[uid] {
                for app in apps {
                    result[app.path] = app
                }
            }

        case .none:
            return [:]
        }

        return result
    }

    func save(_ map: [String: LockedAppConfig]) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        do {
            switch modeLock {
            case .launcher:
                let blockedAppsList = Array(map.values)
                let configDictionary: [String: [LockedAppConfig]] = ["BlockedApps": blockedAppsList]
                let plistData = try encoder.encode(configDictionary)
                try plistData.write(to: configURL, options: .atomic)
                Logfile.core.info("ConfigStore.save launcher: wrote \(blockedAppsList.count) apps")

            case .es:
                let userID = String(getuid())   // uid hiện tại
                let userConfigDictionary: [String: [LockedAppConfig]] = [
                    userID: Array(map.values)
                ]
                let plistData = try encoder.encode(userConfigDictionary)
                try plistData.write(to: configURL, options: .atomic)
                Logfile.core.pInfo("ConfigStore.save ES: wrote \(map.count) apps for uid \(userID)")

            case .none:
                return
            }
        } catch {
            Logfile.core.error("ConfigStore.save failed: \(error.localizedDescription)")
        }
    }

}
