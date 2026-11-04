//
//  ConfigStore+Migration.swift
//  AppLocker
//
//  Created by Doe Phương on 4/11/26.
//

import Foundation
import OSLog

// MARK: - Self-Lockout Sanitization & Legacy Config Migration

extension ConfigStore {
    func sanitizeAppsSelfLockout(
        _ apps: inout [String: LockedAppConfig],
        needsSave: inout Bool
    ) {
        let myBundleID = customSelfBundleID ?? Bundle.main.bundleIdentifier ?? "com.TranPhuong319.AppLocker"
        let myPath = customSelfBundlePath ?? Bundle.main.bundlePath
        let myRealPath = URL(fileURLWithPath: myPath).resolvingSymlinksInPath().path
        let myCDHash = cdHash(for: myPath)

        let containsSelf = apps.values.contains {
            isSelfApp(
                $0,
                currentBundleID: myBundleID,
                currentPath: myPath,
                currentRealPath: myRealPath,
                currentCDHash: myCDHash
            )
        }

        if containsSelf {
            apps = apps.filter {
                !isSelfApp(
                    $0.value,
                    currentBundleID: myBundleID,
                    currentPath: myPath,
                    currentRealPath: myRealPath,
                    currentCDHash: myCDHash
                )
            }
            needsSave = true
            Logfile.policy.notice("[ConfigStore] Self-healing: Removed AppLocker from locked config")
        }
    }

    private func isSelfApp(
        _ config: LockedAppConfig,
        currentBundleID: String,
        currentPath: String,
        currentRealPath: String,
        currentCDHash: String?
    ) -> Bool {
        if !config.bundleID.isEmpty, config.bundleID == currentBundleID {
            return true
        }

        let targetPath = config.path
        let targetRealPath = URL(fileURLWithPath: targetPath).resolvingSymlinksInPath().path
        if targetPath == currentPath || targetRealPath == currentRealPath {
            return true
        }

        if let configCDHash = config.cdhash?.lowercased(), !configCDHash.isEmpty,
           let myCDHash = currentCDHash?.lowercased(),
           configCDHash == myCDHash {
            return true
        }

        return false
    }

    private func parseLegacyConfigs(from data: Data) -> [String: UserConfig] {
        let decoder = PropertyListDecoder()
        if let fullConfig = try? decoder.decode([String: UserConfig].self, from: data) {
            return fullConfig
        }
        if let userConfig = try? decoder.decode(UserConfig.self, from: data) {
            return [String(currentUID): userConfig]
        }
        if let oldDict = try? decoder.decode([String: [LockedAppConfig]].self, from: data) {
            return oldDict.mapValues { UserConfig(isDisabled: false, apps: $0) }
        }
        if let apps = try? decoder.decode([LockedAppConfig].self, from: data) {
            return [String(currentUID): UserConfig(isDisabled: false, apps: apps)]
        }
        return [:]
    }

    func migrateLegacyConfigIfNeeded() {
        let legacyURL = baseDirectoryURL.appendingPathComponent("config.plist")
        guard !FileManager.default.fileExists(atPath: configURL.path),
              FileManager.default.fileExists(atPath: legacyURL.path),
              let legacyData = try? Data(contentsOf: legacyURL) else {
            return
        }

        let configsToMigrate = parseLegacyConfigs(from: legacyData)
        guard !configsToMigrate.isEmpty else { return }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        var allSucceeded = true

        for (uidString, userConfig) in configsToMigrate {
            guard let uid = uid_t(uidString) else { continue }
            let targetURL = UserConfig.configURL(for: uid, baseDirectoryURL: baseDirectoryURL)
            ensureDirectoryExists(targetURL.deletingLastPathComponent())
            do {
                let data = try encoder.encode(userConfig)
                try data.write(to: targetURL, options: .atomic)
            } catch {
                allSucceeded = false
                Logfile.policy.error(
                    "[ConfigStore] Failed to write migrated config for UID \(uidString): \(error.localizedDescription)"
                )
            }
        }
        if allSucceeded {
            try? FileManager.default.removeItem(at: legacyURL)
            Logfile.policy.info("[ConfigStore] Legacy config migrated successfully.")
        }
    }
}
