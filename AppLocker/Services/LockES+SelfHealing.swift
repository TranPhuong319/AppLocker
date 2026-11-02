//
//  LockES+SelfHealing.swift
//  AppLocker
//
//  Created by Doe Phương on 1/11/26.
//

import Foundation

// MARK: - Self-Healing CDHash & Integrity Monitoring
extension LockES {
    /// Handler invoked by AppScannerService when discovered apps on disk have changed.
    func handleInstalledAppsChanged(_ newAllApps: [InstalledApp]) {
        self.allApps = newAllApps
        let migrated = migrateRenamedApps(allApps: newAllApps)
        if migrated {
            onConfigUpdated?()
        }
        verifyAndHealLockedCDHashes()
    }

    /// Update cdhash on disk if it differs from stored configuration.
    func updateCDHashIfNeeded(for path: String, cdhash: String) {
        guard let config = lockedApps[path] else { return }
        let cleanHash = cdhash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanHash.isEmpty, config.cdhash?.lowercased() != cleanHash else { return }

        Logfile.policy.notice(
            """
            [LockES] Auto-healing CDHash for \(config.name ?? path, privacy: .public): \
            \(config.cdhash ?? "nil", privacy: .public) -> \(cleanHash, privacy: .public)
            """
        )
        lockedApps[path]?.cdhash = cleanHash
        save()
    }

    /// Schedule background periodic integrity scan (runs every 30 minutes).
    func setupPeriodicCDHashScan() {
        cdhashPeriodicTask?.cancel()
        cdhashPeriodicTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1800))
                guard !Task.isCancelled, let self = self else { break }
                self.verifyAndHealLockedCDHashes()
            }
        }
    }

    /// Background task to inspect all locked applications and heal outdated hashes.
    func verifyAndHealLockedCDHashes() {
        cdhashScanTask?.cancel()
        let currentLocked = self.lockedApps
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

    nonisolated func detectStaleCDHash(for path: String, config: LockedAppConfig) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let bundle = Bundle(url: URL(fileURLWithPath: path))
        let execPath = bundle?.executablePath ?? path

        guard let currentHash = cdHash(for: execPath) ?? cdHash(for: path) else { return nil }
        let cleanCurrent = currentHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanConfig = config.cdhash?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return cleanCurrent != cleanConfig ? cleanCurrent : nil
    }

    func applyHealedCDHashes(_ updatedHashes: [String: String]) {
        var hasChanged = false
        for (path, newHash) in updatedHashes {
            if let existing = lockedApps[path],
               existing.cdhash?.lowercased() != newHash {
                Logfile.policy.notice(
                    """
                    [LockES] Self-healing CDHash for \(existing.name ?? path, privacy: .public): \
                    \(existing.cdhash ?? "nil", privacy: .public) -> \(newHash, privacy: .public)
                    """
                )
                lockedApps[path]?.cdhash = newHash
                hasChanged = true
            }
        }
        if hasChanged {
            save()
        }
    }
}
