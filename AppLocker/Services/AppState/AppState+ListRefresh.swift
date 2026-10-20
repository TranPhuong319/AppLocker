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

    private func resolveLockedApp(
        path: String,
        config: LockedAppConfig,
        allApps: [InstalledApp]
    ) -> InstalledApp {
        var name = allApps.first(where: {
            $0.path == path || (!config.bundleID.isEmpty && $0.bundleID == config.bundleID)
        })?.name

        if name == nil {
            let displayName = FileManager.default.displayName(atPath: path)
            name = displayName.replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
        }

        let finalName = name ?? config.name ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let source: AppSource = path.hasPrefix("/System") ? .system : .user
        return InstalledApp(name: finalName, bundleID: config.bundleID, path: path, source: source)
    }

    private func prefetchUnlockableIcons(apps: [InstalledApp]) {
        Task(priority: .low) {
            for app in apps.prefix(60) {
                _ = AppIconProvider.shared.icon(for: app.path, size: 32)
            }
        }
    }
}
