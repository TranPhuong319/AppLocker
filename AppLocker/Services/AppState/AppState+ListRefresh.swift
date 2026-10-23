//
//  AppState+ListRefresh.swift
//  AppLocker
//
//  Created by Doe Phương on 9/10/26.
//

import AppKit
import Foundation

extension AppState {
    func refreshAppLists() {
        let allApps = manager.allApps
        if migrateRenamedApps(allApps: allApps) {
            refreshAppLists()
            return
        }

        let lockedPathSet = Set(manager.lockedApps.keys)
        var missingAppsList: [InstalledApp] = []
        var appsToUnhide: [String] = []
        let now = Date()
        var hasPendingCheck = false

        let lockedAppsList: [InstalledApp] = manager.lockedApps.keys.compactMap { path -> InstalledApp? in
            guard let config = manager.lockedApps[path] else { return nil }
            let app = self.resolveLockedApp(path: path, config: config, allApps: allApps)
            let fileExists = FileManager.default.fileExists(atPath: path)
            var isHidden = config.isHidden == true

            if isHidden && fileExists {
                appsToUnhide.append(path)
                isHidden = false
                AppIconProvider.shared.invalidateIcon(for: path)
            }

            let (isConfirmed, isPending) = self.checkMissingStatus(
                path: path,
                isHidden: isHidden,
                now: now,
                fileExists: fileExists
            )
            if isConfirmed { missingAppsList.append(app) }
            if isPending { hasPendingCheck = true }

            guard !isHidden else { return nil }
            return app
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if !appsToUnhide.isEmpty { manager.unhideApps(for: appsToUnhide) }
        if hasPendingCheck { schedulePendingMissingCheck() }

        let unlockable = allApps
            .filter { !lockedPathSet.contains($0.path) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        self.confirmedMissingApps = missingAppsList
        self.lockedAppObjects = lockedAppsList
        self.unlockableApps = unlockable
        self.filteredLockedApps = lockedAppsList.filter(matching: self.searchTextLockApps)
        self.filteredUnlockableApps = unlockable.filter(matching: self.searchTextUnlockableApps)

        prefetchUnlockableIcons(apps: unlockable)
    }

    private func migrateRenamedApps(allApps: [InstalledApp]) -> Bool {
        var hasMigrated = false
        for (path, config) in manager.lockedApps {
            guard !FileManager.default.fileExists(atPath: path),
                  let newApp = allApps.first(where: {
                      !config.bundleID.isEmpty && $0.bundleID == config.bundleID && $0.path != path
                  }) else { continue }
            manager.migrateApp(from: path, to: newApp.path)
            missingAppTimestamps.removeValue(forKey: path)
            hasMigrated = true
        }
        return hasMigrated
    }

    private func resolveLockedApp(
        path: String,
        config: LockedAppConfig,
        allApps: [InstalledApp]
    ) -> InstalledApp {
        let fallbackOriginal = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let existingApp = allApps.first(where: {
            $0.path == path || (!config.bundleID.isEmpty && $0.bundleID == config.bundleID)
        })

        let finalName = existingApp?.name
            ?? AppState.resolveDisplayName(at: path, fallback: config.name ?? fallbackOriginal)
        let originalName = existingApp?.originalName ?? fallbackOriginal
        let source: AppSource = path.hasPrefix("/System") ? .system : .user

        let bundleID = !config.bundleID.isEmpty ? config.bundleID : (existingApp?.bundleID ?? "")

        return InstalledApp(
            name: finalName,
            bundleID: bundleID,
            path: path,
            source: source,
            originalName: originalName
        )
    }

    private func prefetchUnlockableIcons(apps: [InstalledApp]) {
        Task(priority: .low) {
            for app in apps {
                _ = AppIconProvider.shared.icon(for: app.path, size: 32)
            }
        }
    }
}
