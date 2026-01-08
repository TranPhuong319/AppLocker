//
//  LockES.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import AppKit
import Foundation
import CryptoKit

class LockES: LockManagerProtocol {
    @Published var lockedApps: [String: LockedAppConfig] = [:] // keyed by path
    @Published var allApps: [InstalledApp] = []
    private var periodicTimer: Timer?

    init() {
        self.lockedApps = ConfigStore.shared.load()
        self.allApps = self.getInstalledApps()
        Logfile.core.info("Initial scanning started in background...")

        // Quét lần đầu ngay lập tức ở background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.rescanLockedApps()
        }

        // Bắt đầu chu kỳ lặp lại
        self.startPeriodicRescan()
    }

    // MARK: - Installed apps discovery (unchanged)
    func getInstalledApps() -> [InstalledApp] {
        let appsPaths: [String: AppSource] = [
            "/Applications": .user,
            "/System/Applications": .system
        ]

        let selfBundlePath = Bundle.main.bundleURL.path

        var allApps: [InstalledApp] = []
        let fileManager = FileManager.default

        for (dir, source) in appsPaths {
            let dirURL = URL(fileURLWithPath: dir)

            guard let enumerator = fileManager.enumerator(
                at: dirURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "app",
                      !fileURL.lastPathComponent.hasPrefix("."),
                      let bundle = Bundle(url: fileURL),
                      let bundleID = bundle.bundleIdentifier else {
                    continue
                }

                if fileURL.path == selfBundlePath {
                    continue
                }

                let displayName = fileManager.displayName(atPath: fileURL.path)
                    .replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)

                let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
                icon.size = NSSize(width: 32, height: 32)

                allApps.append(
                    InstalledApp(
                        name: displayName,
                        bundleID: bundleID,
                        icon: icon,
                        path: fileURL.path,
                        source: source
                    )
                )
            }
        }

        return allApps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

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
                      let execName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
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
        DispatchQueue.global(qos: .background).async {
            let apps = self.getInstalledApps()
            DispatchQueue.main.async {
                self.allApps = apps
            }
        }
    }

    func isLocked(path: String) -> Bool {
        return lockedApps[path] != nil
    }
}

// MARK: - Auto SHA Rescan
extension LockES {
    func startPeriodicRescan(interval: TimeInterval = 300) {
        if periodicTimer != nil { return }

        // Create a timer on the Main RunLoop but do the heavy lifting in the Background
        periodicTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            // Đẩy việc quét SHA sang thread khác ngay lập tức
            DispatchQueue.global(qos: .utility).async {
                self?.rescanLockedApps()
            }
        }

        // Make sure the timer still runs when the user scrolls or uses the UI
        RunLoop.main.add(periodicTimer!, forMode: .common)
        Logfile.core.info("Start periodic SHA scanning every \(Int(interval)) seconds")
    }

    func stopPeriodicRescan() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    @objc func rescanLockedApps() {
        // Run the heavy SHA calculation on the current thread (usually background)
        Logfile.core.info("Re-scanning the SHA of locked apps...")
        var changed = false
        var updatedMap = self.lockedApps // Copy locally for processing

        for (path, cfg) in updatedMap {
            let exeFile = cfg.execFile ?? "Unknown"
            let execPath = "\(path)/Contents/MacOS/\(exeFile)"
            guard FileManager.default.fileExists(atPath: execPath) else { continue }

            guard let newSHA = computeSHA(forPath: execPath), !newSHA.isEmpty else {
                continue
            }

            if cfg.sha256 != newSHA {
                let name = cfg.name ?? "Unknown"
                Logfile.core.warning("SHA changes for \(name): \(cfg.sha256.prefix(8)) → \(newSHA.prefix(8))")

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
