//
//  LockES+LockOperations.swift
//  AppLocker
//
//  Created by Doe Phương on 1/11/26.
//

import AppKit
import Foundation

// MARK: - App Lock Operations & List Management
extension LockES {
    /// Toggle lock state for a set of application paths.
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
                    resolvedExecPath = FileManager.default.fileExists(atPath: potentialPath) ? potentialPath : nil
                }

                guard let execPath = resolvedExecPath else {
                    Logfile.policy.error("[LockES] Cannot resolve executable path for \(path, privacy: .public)")
                    continue
                }

                // Get filename for config
                let execName = URL(fileURLWithPath: execPath).lastPathComponent

                let fallbackOriginal = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                let appName = allApps.first(where: { $0.path == path })?.name
                    ?? InstalledApp.resolveDisplayName(at: path, fallback: fallbackOriginal)
                let cdhash = cdHash(for: execPath) ?? cdHash(for: path)
                let bundleID = bundle.bundleIdentifier ?? ""

                let lockedAppConfig = LockedAppConfig(
                    bundleID: bundleID,
                    path: path,
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

    /// Mark locked apps as hidden in the locked list.
    func hideApps(for paths: [String]) {
        var hasConfigChanged = false
        for path in paths where lockedApps[path] != nil {
            lockedApps[path]?.isHidden = true
            hasConfigChanged = true
        }
        if hasConfigChanged {
            save()
        }
    }

    /// Unhide previously hidden locked apps.
    func unhideApps(for paths: [String]) {
        var hasConfigChanged = false
        for path in paths where lockedApps[path]?.isHidden == true {
            lockedApps[path]?.isHidden = false
            hasConfigChanged = true
        }
        if hasConfigChanged {
            save()
        }
    }

    /// Remove applications completely from the locked configuration.
    func removeApps(for paths: [String]) {
        var hasConfigChanged = false
        for path in paths where lockedApps.removeValue(forKey: path) != nil {
            hasConfigChanged = true
        }
        if hasConfigChanged {
            save()
        }
    }

    /// Migrate an app configuration from an old path to a new path.
    func migrateApp(from oldPath: String, to newPath: String) {
        guard let config = lockedApps.removeValue(forKey: oldPath) else { return }
        let cdhash = cdHash(for: newPath) ?? config.cdhash
        let appName = InstalledApp.resolveDisplayName(at: newPath, fallback: config.name ?? "")
        lockedApps[newPath] = LockedAppConfig(
            bundleID: config.bundleID,
            path: newPath,
            execFile: URL(fileURLWithPath: newPath).deletingPathExtension().lastPathComponent,
            name: appName,
            cdhash: cdhash,
            isHidden: config.isHidden
        )
        save()
    }

    /// Check and migrate any apps whose bundle identifier matches but path has changed.
    @discardableResult
    func migrateRenamedApps(allApps: [InstalledApp]) -> Bool {
        var hasMigrated = false
        for (path, config) in lockedApps {
            guard !FileManager.default.fileExists(atPath: path),
                  let newApp = allApps.first(where: {
                      !config.bundleID.isEmpty && $0.bundleID == config.bundleID && $0.path != path
                  }) else { continue }
            migrateApp(from: path, to: newApp.path)
            hasMigrated = true
        }
        return hasMigrated
    }
}
