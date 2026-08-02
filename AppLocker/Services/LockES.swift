//
//  LockES.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import AppKit
import CryptoKit
import Foundation

class LockES: LockManagerProtocol {
    @Published var lockedApps: [String: LockedAppConfig] = [:]  // keyed by path
    @Published var allApps: [InstalledApp] = []
    @Published var isProtectionDisabled: Bool = false
    private var fsWatcher: FSEventsMonitoringService?

    init() {
        // Defer loading to bootstrap() to allow ES Handshake first
    }

    func bootstrap() {
        ConfigStore.shared.performHandshake { [weak self] success in
            guard let self = self else { return }
            Logfile.core.info("ES Handshake finished (success=\(success)). Proceeeding to load config.")

            // Safe to load config now (we are Muted or Launcher mode)
            let loaded = ConfigStore.shared.load()

            DispatchQueue.main.async {
                self.lockedApps = loaded.apps
                self.isProtectionDisabled = loaded.isDisabled

                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.migrateLegacyConfigsIfNeeded(isLegacyFormat: loaded.isLegacyFormat)
                }
            }

            self.setupFSEvents()
        }
    }

    private func migrateLegacyConfigsIfNeeded(isLegacyFormat: Bool = false) {
        var needsSave = isLegacyFormat
        var updatedApps = self.lockedApps

        for (path, var appConfig) in updatedApps {
            var updated = migrateCDHash(for: &appConfig, defaultPath: path)
            if migrateExecFile(for: &appConfig) { updated = true }
            if migrateName(for: &appConfig, path: path) { updated = true }

            if updated {
                updatedApps[path] = appConfig
                needsSave = true
            }
        }

        if needsSave {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lockedApps = updatedApps
                self.save()
                Logfile.core.info("Auto-migrated legacy app configs to unified ES format and saved to disk.")
            }
        }
    }

    private func migrateCDHash(for appConfig: inout LockedAppConfig, defaultPath: String) -> Bool {
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
                Logfile.core.info("Migrated legacy config for \(appName): cdhash (\(prefix))")
                return true
            }
        } else if appConfig.sha256 != nil {
            appConfig.sha256 = nil
            return true
        }
        return false
    }

    private func migrateExecFile(for appConfig: inout LockedAppConfig) -> Bool {
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

    private func migrateName(for appConfig: inout LockedAppConfig, path: String) -> Bool {
        if appConfig.name == nil || appConfig.name?.isEmpty == true {
            let name = FileManager.default.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
            appConfig.name = name
            return true
        }
        return false
    }

    private func setupFSEvents() {
        fsWatcher = FSEventsMonitoringService(paths: ["/Applications", "/System/Applications"])
        fsWatcher?.delegate = self
        fsWatcher?.start()
        Logfile.core.info("FSEvents monitoring started for applications directories")
    }

    // MARK: - Installed apps discovery (Removed in favor of Spotlight)

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
                    Logfile.core.error("Cannot create Bundle for \(path)")
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
                    Logfile.core.error("Cannot resolve executable path for \(path)")
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

    func reloadAllApps() {
        // Spotlight updates automatically
    }

    func isLocked(path: String) -> Bool {
        return lockedApps[path] != nil
    }
}

// MARK: - FSEvents Delegate
extension LockES: FSEventsDelegate {
    func fileSystemChanged(at paths: [String]) {
        // App changes monitored; cdhash and path matching are handled dynamically without heavy SHA re-calculation
    }
}
