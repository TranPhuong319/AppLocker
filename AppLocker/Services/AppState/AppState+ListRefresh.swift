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
        self.verifyAndHealLockedCDHashes()
    }

    func verifyAndHealLockedCDHashes() {
        cdhashScanTask?.cancel()
        let currentLocked = manager.lockedApps
        guard !currentLocked.isEmpty else { return }

        cdhashScanTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var updatedHashes: [String: String] = [:]

            for (path, config) in currentLocked {
                guard !Task.isCancelled else { return }
                if let newHash = self.detectStaleCDHash(for: path, config: config) {
                    updatedHashes[path] = newHash
                }
            }

            guard !updatedHashes.isEmpty, !Task.isCancelled else { return }
            await self.applyHealedCDHashes(updatedHashes)
        }
    }

    nonisolated private func detectStaleCDHash(for path: String, config: LockedAppConfig) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let bundle = Bundle(url: URL(fileURLWithPath: path))
        let execPath = bundle?.executablePath ?? path

        guard let currentHash = cdHash(for: execPath) ?? cdHash(for: path) else { return nil }
        let cleanCurrent = currentHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanConfig = config.cdhash?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return cleanCurrent != cleanConfig ? cleanCurrent : nil
    }

    private func applyHealedCDHashes(_ updatedHashes: [String: String]) {
        var hasChanged = false
        for (path, newHash) in updatedHashes {
            if let existing = manager.lockedApps[path],
               existing.cdhash?.lowercased() != newHash {
                Logfile.policy.notice(
                    """
                    [LockES] Self-healing CDHash for \(existing.name ?? path, privacy: .public): \
                    \(existing.cdhash ?? "nil", privacy: .public) -> \(newHash, privacy: .public)
                    """
                )
                manager.lockedApps[path]?.cdhash = newHash
                hasChanged = true
            }
        }
        if hasChanged {
            manager.save()
        }
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
}
