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
        guard let config = UserConfig.load(for: getuid()) else {
            return .empty
        }

        var apps: [String: LockedAppConfig] = [:]
        for app in config.apps {
            apps[app.path] = app
        }

        let autoLockTimeout = config.autoLockTimeoutMinutes
            ?? UserDefaults.standard.integer(forKey: "autoLockTimeoutMinutes")

        // Persist timeout on first load if missing from saved config
        if config.autoLockTimeoutMinutes == nil {
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
}
