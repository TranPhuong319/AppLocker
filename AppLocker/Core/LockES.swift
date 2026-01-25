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
                self.lockedApps = loaded
                // Update Extension with loaded apps immediately
                self.publishToExtension()
            }
            
            Logfile.core.info("Initial scanning started in background...")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.rescanLockedApps()
            }
            
            self.setupFSEvents()
        }
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
        ConfigStore.shared.save(self.lockedApps)
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

                let appName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                guard let sha = computeSHA(forPath: execPath) else {
                    Logfile.core.error("Cannot compute SHA for \(execPath)")
                    continue
                }
                let bundleID = bundle.bundleIdentifier ?? ""

                let mode = modeLock?.rawValue ?? AppMode.es.rawValue
                let lockedAppConfig = LockedAppConfig(
                    bundleID: bundleID,
                    path: path,
                    sha256: sha,
                    blockMode: mode,
                    execFile: execName,
                    name: appName
                )
                lockedApps[path] = lockedAppConfig
                hasConfigChanged = true
            }
        }

        if hasConfigChanged {
            save()
            publishToExtension()
        }
    }

    // MARK: - Send config to ES Extension
    func publishToExtension() {
        let blockedAppsDictList = lockedApps.values.map { $0.toDict() }
        DispatchQueue.global().async {
            ESXPCClient.shared.updateBlockedApps(blockedAppsDictList)
        }
    }

    func reloadAllApps() {
        // Spotlight updates automatically
    }

    func isLocked(path: String) -> Bool {
        return lockedApps[path] != nil
    }
}

// MARK: - Auto SHA Rescan
extension LockES: FSEventsDelegate {
    func fileSystemChanged(at paths: [String]) {
        // Lọc các đường dẫn thuộc các app đang bị khóa
        let lockedPaths = lockedApps.keys
        var appsToUpdate: [String] = []

        for changedPath in paths {
            for lockedPath in lockedPaths {
                if changedPath.hasPrefix(lockedPath) {
                    appsToUpdate.append(lockedPath)
                }
            }
        }

        guard !appsToUpdate.isEmpty else { return }

        // Loại bỏ trùng lặp và update SHA
        let uniqueApps = Set(appsToUpdate)
        Logfile.core.info(
            "FSEvents detected changes in \(uniqueApps.count) locked apps. Updating SHAs...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.updateSHAs(for: Array(uniqueApps))
        }
    }

    private func updateSHAs(for paths: [String]) {
        var hasChanges = false
        var updatedLockedAppsMap = self.lockedApps

        for path in paths {
            guard let appConfig = updatedLockedAppsMap[path] else { continue }
            let executableFileName = appConfig.execFile ?? "Unknown"
            let execPath = "\(path)/Contents/MacOS/\(executableFileName)"

            guard FileManager.default.fileExists(atPath: execPath) else { continue }
            guard let newSHAValue = computeSHA(forPath: execPath), !newSHAValue.isEmpty else { continue }

            if appConfig.sha256 != newSHAValue {
                Logfile.core.warning(
                    "SHA auto-updated for \(appConfig.name ?? "Unknown"): \(appConfig.sha256.prefix(8)) → \(newSHAValue.prefix(8))"
                )
                let updatedCfg = LockedAppConfig(
                    bundleID: appConfig.bundleID,
                    path: appConfig.path,
                    sha256: newSHAValue,
                    blockMode: appConfig.blockMode,
                    execFile: appConfig.execFile,
                    name: appConfig.name
                )
                updatedLockedAppsMap[path] = updatedCfg
                hasChanges = true
            }
        }

        if hasChanges {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lockedApps = updatedLockedAppsMap
                self.save()
                self.publishToExtension()
            }
        }
    }

    func stopPeriodicRescan() {
        fsWatcher?.stop()
        fsWatcher = nil
    }

    @objc func rescanLockedApps() {
        // Run the heavy SHA calculation on the current thread (usually background)
        Logfile.core.info("Re-scanning the SHA of locked apps...")
        var hasChanges = false
        var updatedLockedAppsMap = self.lockedApps  // Copy locally for processing

        for (path, appConfig) in updatedLockedAppsMap {
            let executableFileName = appConfig.execFile ?? "Unknown"
            let execPath = "\(path)/Contents/MacOS/\(executableFileName)"
            guard FileManager.default.fileExists(atPath: execPath) else { continue }

            guard let newSHAValue = computeSHA(forPath: execPath), !newSHAValue.isEmpty else {
                continue
            }

            if appConfig.sha256 != newSHAValue {
                let name = appConfig.name ?? "Unknown"
                Logfile.core.warning(
                    "SHA changes for \(name): \(appConfig.sha256.prefix(8)) → \(newSHAValue.prefix(8))")

                let updatedCfg = LockedAppConfig(
                    bundleID: appConfig.bundleID,
                    path: appConfig.path,
                    sha256: newSHAValue,
                    blockMode: appConfig.blockMode,
                    execFile: appConfig.execFile,
                    name: appConfig.name
                )
                updatedLockedAppsMap[path] = updatedCfg
                hasChanges = true
            }
        }

        if hasChanges {
            // Push the update of the original data and save the file to the Main Thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lockedApps = updatedLockedAppsMap
                self.save()
                self.publishToExtension()
                Logfile.core.info("New SHA updated and published")
            }
        } else {
            Logfile.core.info("No SHA changes")
        }
    }
}
