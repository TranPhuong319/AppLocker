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

final class ConfigStore: @unchecked Sendable {
    static let shared = ConfigStore()
    static let baseDirectoryURL = UserConfig.baseDirectoryURL

    let baseDirectoryURL: URL
    let userDefaults: UserDefaults
    let currentUID: uid_t
    let customSelfBundleID: String?
    let customSelfBundlePath: String?

    var userDirectoryURL: URL {
        configURL.deletingLastPathComponent()
    }

    var configURL: URL {
        UserConfig.configURL(for: currentUID, baseDirectoryURL: baseDirectoryURL)
    }

    init(
        baseDirectoryURL: URL = UserConfig.baseDirectoryURL,
        userDefaults: UserDefaults = .standard,
        uid: uid_t = getuid(),
        selfBundleID: String? = nil,
        selfBundlePath: String? = nil
    ) {
        self.baseDirectoryURL = baseDirectoryURL
        self.userDefaults = userDefaults
        self.currentUID = uid
        self.customSelfBundleID = selfBundleID
        self.customSelfBundlePath = selfBundlePath
        ensureDirectoryExists(self.baseDirectoryURL)
        ensureDirectoryExists(userDirectoryURL)
    }

    func ensureDirectoryExists(_ url: URL) {
        #if DEBUG
        guard !PreviewEnvironment.isRunningInPreview else { return }
        #endif
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

        guard let config = UserConfig.load(for: currentUID, baseDirectoryURL: baseDirectoryURL) else {
            return ConfigLoadResult(
                apps: [:],
                isDisabled: false,
                allowIncomingCalls: true,
                autoLockTimeoutMinutes: userDefaults.integer(forKey: "autoLockTimeoutMinutes")
            )
        }

        var apps: [String: LockedAppConfig] = [:]
        for app in config.apps {
            apps[app.path] = app
        }

        let autoLockTimeout = config.autoLockTimeoutMinutes
            ?? userDefaults.integer(forKey: "autoLockTimeoutMinutes")

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

    func save(
        apps map: [String: LockedAppConfig],
        isDisabled: Bool,
        allowIncomingCalls: Bool = true,
        autoLockTimeoutMinutes: Int = 0
    ) {
        #if DEBUG
        guard !PreviewEnvironment.isRunningInPreview else { return }
        #endif
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
                \(self.currentUID, privacy: .public) at \(self.configURL.path, privacy: .public)
                """
            )
        } catch {
            Logfile.policy.error("[ConfigStore] Save failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func removeConfig(purgeAll: Bool = false) -> Bool {
        #if DEBUG
        guard !PreviewEnvironment.isRunningInPreview else { return true }
        #endif
        if userDefaults === UserDefaults.standard, let domain = Bundle.main.bundleIdentifier {
            userDefaults.removePersistentDomain(forName: domain)
        }
        do {
            let targetURL = purgeAll ? baseDirectoryURL : userDirectoryURL
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            return true
        } catch {
            Logfile.policy.error("[ConfigStore] Error deleting config directory: \(error.localizedDescription)")
            return false
        }
    }
}
