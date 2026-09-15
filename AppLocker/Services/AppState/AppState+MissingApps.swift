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
        self.showingMissingAppsSheet = false
        self.manager.hideApps(for: paths)
        for path in paths {
            self.missingAppTimestamps.removeValue(forKey: path)
        }
        self.refreshAppLists()
    }

    func deleteMissingApps(paths: [String]) {
        let confirmation = AlertShow.show(
            title: String(localized: "Remove Missing Applications"),
            message: String(
                localized: "Are you sure you want to remove the missing applications from the lock list?"
            ),
            style: .critical,
            buttons: [
                String(localized: "Remove"),
                String(localized: "Cancel")
            ],
            cancelIndex: 1,
            defaultIndex: 0
        )

        guard case .button(let index, _) = confirmation, index == 0 else { return }

        self.showingMissingAppsSheet = false
        self.manager.removeApps(for: paths)
        for path in paths {
            self.missingAppTimestamps.removeValue(forKey: path)
        }
        self.refreshAppLists()
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
