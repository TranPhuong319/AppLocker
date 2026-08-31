//
//  LockES.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import AppKit
import CryptoKit
import Foundation
import Observation

@Observable
@MainActor
class LockES: LockManagerProtocol {
    var lockedApps: [String: LockedAppConfig] = [:]  // keyed by path
    var allApps: [InstalledApp] = []
    var isProtectionDisabled: Bool = false

    var onConfigUpdated: (() -> Void)?

    init() {
        // Defer loading to bootstrap() to allow ES Handshake first
    }

    func bootstrap(onUpdate: (() -> Void)? = nil) {
        if let onUpdate = onUpdate {
            self.onConfigUpdated = onUpdate
        }
        ConfigStore.shared.performHandshake { [weak self] success in
            guard let self else { return }
            Logfile.policy.info(
                "[LockES] ES Handshake finished (success=\(success, privacy: .public)). Proceeding to load config."
            )

            // Safe to load config now (we are Muted or Launcher mode)
            let loaded = ConfigStore.shared.load()

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lockedApps = loaded.apps
                self.isProtectionDisabled = loaded.isDisabled
                self.onConfigUpdated?()
                self.migrateLegacyConfigsIfNeeded(appsToMigrate: loaded.apps, isLegacyFormat: loaded.isLegacyFormat)
            }
        }
    }

    private func migrateLegacyConfigsIfNeeded(appsToMigrate: [String: LockedAppConfig], isLegacyFormat: Bool) {
        Task(priority: .high) { [weak self] in
            var needsSave = isLegacyFormat
            var updatedApps = appsToMigrate

            for (path, var appConfig) in updatedApps {
                var updated = LockES.migrateCDHash(for: &appConfig, defaultPath: path)
                if LockES.migrateExecFile(for: &appConfig) { updated = true }
                if LockES.migrateName(for: &appConfig, path: path) { updated = true }

                if updated {
                    updatedApps[path] = appConfig
                    needsSave = true
                }
            }

            if needsSave {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.lockedApps = updatedApps
                    self.save()
                    Logfile.policy.info(
                        "[LockES] Auto-migrated legacy app configs to unified ES format and saved to disk."
                    )
                }
            }
        }
    }

    private nonisolated static func migrateCDHash(for appConfig: inout LockedAppConfig, defaultPath: String) -> Bool {
        if appConfig.cdhash == nil || appConfig.cdhash?.isEmpty == true {
            var execPath = appConfig.path
            if let bundle = Bundle(url: URL(fileURLWithPath: appConfig.path)) {
                execPath = bundle.executablePath ?? appConfig.path
            }

            if let cdhash = extractCDHash(forPath: execPath) ?? extractCDHash(forPath: appConfig.path) {
                appConfig.cdhash = cdhash
                appConfig.sha256 = nil
                let appName = appConfig.name ?? defaultPath
                let prefix = String(cdhash.prefix(8))
                Logfile.policy.debug(
                    """
                    [LockES] Migrated legacy config for \(appName, privacy: .public): \
                    cdhash (\(prefix, privacy: .public))
                    """
                )
                return true
            }
        } else if appConfig.sha256 != nil {
            appConfig.sha256 = nil
            return true
        }
        return false
    }

    private nonisolated static func migrateExecFile(for appConfig: inout LockedAppConfig) -> Bool {
        if appConfig.execFile == nil || appConfig.execFile?.isEmpty == true {
            var execPath = appConfig.path
            if let bundle = Bundle(url: URL(fileURLWithPath: appConfig.path)) {
                execPath = bundle.executablePath ?? appConfig.path
            }
            appConfig.execFile = URL(fileURLWithPath: execPath).lastPathComponent
            return true
        }
        return false
    }

    private nonisolated static func migrateName(for appConfig: inout LockedAppConfig, path: String) -> Bool {
        if appConfig.name == nil || appConfig.name?.isEmpty == true {
            let name = FileManager.default.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
            appConfig.name = name
            return true
        }
        return false
    }

    // MARK: - Persistence helper
    func save() {
        ConfigStore.shared.save(apps: self.lockedApps, isDisabled: self.isProtectionDisabled)
    }

    func setProtectionDisabled(_ disabled: Bool) {
        self.isProtectionDisabled = disabled
        self.save()
    }

    // MARK: - Toggle lock (ES mode: chỉ ghi config và publish)
    func toggleLock(for paths: [String]) {
        var hasConfigChanged = false

        for path in paths {
            if lockedApps.removeValue(forKey: path) != nil {
                hasConfigChanged = true
            } else {
                guard let bundle = Bundle(url: URL(fileURLWithPath: path)) else {
                    Logfile.policy.error("[LockES] Cannot create Bundle for \(path, privacy: .public)")
                    continue
                }

                // 1. Try standard Bundle resolution
                var resolvedExecPath = bundle.executablePath

                // 2. Fallback for broken Info.plist (Empty CFBundleExecutable)
                if resolvedExecPath == nil {
                    let appName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                    let potentialPath = "\(path)/Contents/MacOS/\(appName)"
                    if FileManager.default.fileExists(atPath: potentialPath) {
                        resolvedExecPath = potentialPath
                    }
                }

                guard let execPath = resolvedExecPath else {
                    Logfile.policy.error("[LockES] Cannot resolve executable path for \(path, privacy: .public)")
                    continue
                }

                // Get filename for config
                let execName = URL(fileURLWithPath: execPath).lastPathComponent

                let appName = FileManager.default.displayName(atPath: path)
                    .replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
                let cdhash = extractCDHash(forPath: execPath) ?? extractCDHash(forPath: path)
                let bundleID = bundle.bundleIdentifier ?? ""

                let lockedAppConfig = LockedAppConfig(
                    bundleID: bundleID,
                    path: path,
                    sha256: nil,
                    execFile: execName,
                    name: appName,
                    cdhash: cdhash
                )
                lockedApps[path] = lockedAppConfig
                hasConfigChanged = true
            }
        }

        if hasConfigChanged {
            save()
        }
    }

    func isLocked(path: String) -> Bool {
        if isProtectionDisabled { return false }
        return lockedApps[path] != nil
    }
}
