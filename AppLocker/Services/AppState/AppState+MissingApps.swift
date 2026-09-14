//
//  AppState+MissingApps.swift
//  AppLocker
//
//  Created by Doe Phương on 14/9/26.
//

import AppKit
import Foundation

// MARK: - Missing Apps Handling

extension AppState {
    func checkMissingStatus(
        path: String,
        isHidden: Bool,
        now: Date,
        fileExists: Bool
    ) -> (isConfirmed: Bool, isPending: Bool) {
        guard !fileExists else {
            if missingAppTimestamps.removeValue(forKey: path) != nil {
                AppIconProvider.shared.invalidateIcon(forPath: path)
            }
            return (false, false)
        }
        guard !isHidden else { return (false, false) }
        let firstDetected = missingAppTimestamps[path] ?? now
        missingAppTimestamps[path] = firstDetected
        let isConfirmed = now.timeIntervalSince(firstDetected) >= 3.0
        return (isConfirmed, !isConfirmed)
    }

    func schedulePendingMissingCheck() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.0))
            guard !Task.isCancelled, let self = self else { return }
            self.refreshAppLists()
        }
    }

    func hideMissingApps(paths: [String]) {
        AuthenticationManager.authenticate(
            reason: String(localized: "authenticate to hide missing applications")
        ) { [weak self] success, _ in
            guard success, let self = self else { return }
            self.manager.hideApps(for: paths)
            for path in paths {
                self.missingAppTimestamps.removeValue(forKey: path)
            }
            self.refreshAppLists()
            self.showingMissingAppsSheet = false
        }
    }

    func deleteMissingApps(paths: [String]) {
        AuthenticationManager.authenticate(
            reason: String(localized: "authenticate to remove missing applications")
        ) { [weak self] success, _ in
            guard success, let self = self else { return }
            self.manager.removeApps(for: paths)
            for path in paths {
                self.missingAppTimestamps.removeValue(forKey: path)
            }
            self.refreshAppLists()
            self.showingMissingAppsSheet = false
        }
    }

    @objc func openMissingApps() {
        showingMissingAppsSheet = true
    }

    @objc func closeMissingApps() {
        showingMissingAppsSheet = false
    }

    @objc func hideAllMissingApps() {
        let paths = confirmedMissingApps.map(\.path)
        guard !paths.isEmpty else { return }
        hideMissingApps(paths: paths)
    }

    @objc func removeAllMissingApps() {
        let paths = confirmedMissingApps.map(\.path)
        guard !paths.isEmpty else { return }
        deleteMissingApps(paths: paths)
    }
}
