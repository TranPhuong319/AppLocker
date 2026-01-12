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
        self.lockedApps = ConfigStore.shared.load()
        Logfile.core.info("Initial scanning started in background...")

        // Quét lần đầu ngay lập tức ở background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.rescanLockedApps()
        }

        // Thay thế Timer bằng FSEvents
        setupFSEvents()
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
        var didChange = false

        for path in paths {
            if lockedApps.removeValue(forKey: path) != nil {
                didChange = true
            } else {
                guard let bundle = Bundle(url: URL(fileURLWithPath: path)),
                    let execName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable")
                        as? String
                else {
                    Logfile.core.error("Cannot read Info.plist for \(path)")
                    continue
                }

                let appName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                let execPath = "\(path)/Contents/MacOS/\(execName)"
                guard let sha = computeSHA(forPath: execPath) else {
                    Logfile.core.error("Cannot compute SHA for \(execPath)")
                    continue
                }
                let bundleID = bundle.bundleIdentifier ?? ""

                let mode = modeLock?.rawValue ?? AppMode.es.rawValue
                let cfg = LockedAppConfig(
                    bundleID: bundleID,
                    path: path,
                    sha256: sha,
                    blockMode: mode,
                    execFile: execName,
                    name: appName
                )
                lockedApps[path] = cfg
                didChange = true
            }
        }

        if didChange {
            save()
            publishToExtension()
        }
    }

    // MARK: - Send config to ES Extension
    func publishToExtension() {
        let arr = lockedApps.values.map { $0.toDict() }
        DispatchQueue.global().async {
            ESXPCClient.shared.updateBlockedApps(arr)
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
        var changed = false
        var updatedMap = self.lockedApps

        for path in paths {
            guard let cfg = updatedMap[path] else { continue }
            let exeFile = cfg.execFile ?? "Unknown"
            let execPath = "\(path)/Contents/MacOS/\(exeFile)"

            guard FileManager.default.fileExists(atPath: execPath) else { continue }
            guard let newSHA = computeSHA(forPath: execPath), !newSHA.isEmpty else { continue }

            if cfg.sha256 != newSHA {
                Logfile.core.warning(
                    "SHA auto-updated for \(cfg.name ?? "Unknown"): \(cfg.sha256.prefix(8)) → \(newSHA.prefix(8))"
                )
                let updatedCfg = LockedAppConfig(
                    bundleID: cfg.bundleID,
                    path: cfg.path,
                    sha256: newSHA,
                    blockMode: cfg.blockMode,
                    execFile: cfg.execFile,
                    name: cfg.name
                )
                updatedMap[path] = updatedCfg
                changed = true
            }
        }

        if changed {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lockedApps = updatedMap
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
        var changed = false
        var updatedMap = self.lockedApps  // Copy locally for processing

        for (path, cfg) in updatedMap {
            let exeFile = cfg.execFile ?? "Unknown"
            let execPath = "\(path)/Contents/MacOS/\(exeFile)"
            guard FileManager.default.fileExists(atPath: execPath) else { continue }

            guard let newSHA = computeSHA(forPath: execPath), !newSHA.isEmpty else {
                continue
            }

            if cfg.sha256 != newSHA {
                let name = cfg.name ?? "Unknown"
                Logfile.core.warning(
                    "SHA changes for \(name): \(cfg.sha256.prefix(8)) → \(newSHA.prefix(8))")

                let updatedCfg = LockedAppConfig(
                    bundleID: cfg.bundleID,
                    path: cfg.path,
                    sha256: newSHA,
                    blockMode: cfg.blockMode,
                    execFile: cfg.execFile,
                    name: cfg.name
                )
                updatedMap[path] = updatedCfg
                changed = true
            }
        }

        if changed {
            // Push the update of the original data and save the file to the Main Thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lockedApps = updatedMap
                self.save()
                self.publishToExtension()
                Logfile.core.info("New SHA updated and published")
            }
        } else {
            Logfile.core.info("No SHA changes")
        }
    }
}
