//
//  ConfigStore.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation
import OSLog

struct ConfigLoadResult {
    let apps: [String: LockedAppConfig]
    let isDisabled: Bool
    let allowIncomingCalls: Bool
    let autoLockTimeoutMinutes: Int

    static let empty = ConfigLoadResult(
        apps: [:],
        isDisabled: false,
        allowIncomingCalls: true,
        autoLockTimeoutMinutes: UserDefaults.standard.integer(forKey: "autoLockTimeoutMinutes")
    )
}

final class ConfigStore: Sendable {
    static let shared = ConfigStore()
    static let baseDirectoryURL = UserConfig.baseDirectoryURL

    var userDirectoryURL: URL {
        configURL.deletingLastPathComponent()
    }

    var configURL: URL {
        UserConfig.configURL(for: getuid())
    }

    private init() {
        ensureDirectoryExists(Self.baseDirectoryURL)
        ensureDirectoryExists(userDirectoryURL)
    }

    private func ensureDirectoryExists(_ url: URL) {
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: attributes
            )
        } catch {
            Logfile.policy.error(
                """
                [ConfigStore] Failed to create directory at \(url.path, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """
            )
        }
    }

    func performHandshake(completion: @escaping @Sendable (Bool) -> Void) {
        guard ExtensionInstaller.isExtensionInstalled else {
            completion(false)
            return
        }
        let currentProcessID = getpid()
        ESXPCClient.shared.allowConfigAccess(currentProcessID) { success in
            completion(success)
        }
    }

    func load() -> ConfigLoadResult {
        migrateLegacyConfigIfNeeded()

        guard let config = UserConfig.load(for: getuid()) else {
            return .empty
        }

        var apps: [String: LockedAppConfig] = [:]
        for app in config.apps {
            apps[app.path] = app
        }

        let autoLockTimeout = config.autoLockTimeoutMinutes
            ?? UserDefaults.standard.integer(forKey: "autoLockTimeoutMinutes")

        var needsSave = config.autoLockTimeoutMinutes == nil
        sanitizeAppsSelfLockout(&apps, needsSave: &needsSave)

        if needsSave {
            save(
                apps: apps,
                isDisabled: config.isDisabled,
                allowIncomingCalls: config.allowIncomingCalls ?? true,
                autoLockTimeoutMinutes: autoLockTimeout
            )
        }

        return ConfigLoadResult(
            apps: apps,
            isDisabled: config.isDisabled,
            allowIncomingCalls: config.allowIncomingCalls ?? true,
            autoLockTimeoutMinutes: autoLockTimeout
        )
    }

    private func sanitizeAppsSelfLockout(
        _ apps: inout [String: LockedAppConfig],
        needsSave: inout Bool
    ) {
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.TranPhuong319.AppLocker"
        let myPath = Bundle.main.bundlePath
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

    func save(
        apps map: [String: LockedAppConfig],
        isDisabled: Bool,
        allowIncomingCalls: Bool = true,
        autoLockTimeoutMinutes: Int = 0
    ) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        do {
            ensureDirectoryExists(userDirectoryURL)

            let userConfig = UserConfig(
                isDisabled: isDisabled,
                apps: Array(map.values),
                allowIncomingCalls: allowIncomingCalls,
                autoLockTimeoutMinutes: autoLockTimeoutMinutes
            )
            let plistData = try encoder.encode(userConfig)
            try plistData.write(to: configURL, options: .atomic)

            var attributes = [FileAttributeKey: Any]()
            attributes[.posixPermissions] = 0o666
            try FileManager.default.setAttributes(attributes, ofItemAtPath: configURL.path)

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

    @discardableResult
    func removeConfig(purgeAll: Bool = false) -> Bool {
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        do {
            let targetURL = purgeAll ? Self.baseDirectoryURL : userDirectoryURL
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            return true
        } catch {
            Logfile.policy.error("[ConfigStore] Error deleting config directory: \(error.localizedDescription)")
            return false
        }
    }

    private func migrateLegacyConfigIfNeeded() {
        let legacyURL = Self.baseDirectoryURL.appendingPathComponent("config.plist")
        guard !FileManager.default.fileExists(atPath: configURL.path),
              FileManager.default.fileExists(atPath: legacyURL.path),
              let legacyData = try? Data(contentsOf: legacyURL) else {
            return
        }

        let decoder = PropertyListDecoder()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        var configsToMigrate: [String: UserConfig] = [:]
        if let fullConfig = try? decoder.decode([String: UserConfig].self, from: legacyData) {
            configsToMigrate = fullConfig
        } else if let userConfig = try? decoder.decode(UserConfig.self, from: legacyData) {
            configsToMigrate[String(getuid())] = userConfig
        } else if let oldDict = try? decoder.decode([String: [LockedAppConfig]].self, from: legacyData) {
            for (key, apps) in oldDict {
                configsToMigrate[key] = UserConfig(isDisabled: false, apps: apps)
            }
        } else if let apps = try? decoder.decode([LockedAppConfig].self, from: legacyData) {
            configsToMigrate[String(getuid())] = UserConfig(isDisabled: false, apps: apps)
        }

        guard !configsToMigrate.isEmpty else { return }
        for (uidString, userConfig) in configsToMigrate {
            guard let uid = uid_t(uidString) else { continue }
            let targetURL = UserConfig.configURL(for: uid)
            ensureDirectoryExists(targetURL.deletingLastPathComponent())
            if let data = try? encoder.encode(userConfig) {
                try? data.write(to: targetURL, options: .atomic)
            }
        }
        try? FileManager.default.removeItem(at: legacyURL)
        Logfile.policy.info("[ConfigStore] Legacy config migrated successfully.")
    }
}
