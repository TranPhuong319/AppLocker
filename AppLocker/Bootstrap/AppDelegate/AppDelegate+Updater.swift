//
//  AppDelegate+Updater.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit

extension AppDelegate {
    func setupUpdateObserver() {
        NotificationCenter.default.addObserver(
            forName: .appLockerPendingUpdateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let hasUpdate = notification.object != nil
            MainActor.assumeIsolated {
                self?.handlePendingUpdateChange(hasUpdate: hasUpdate)
            }
        }
    }

    private func handlePendingUpdateChange(hasUpdate: Bool) {
        guard hasUpdate else {
            Logfile.app.debug("[Updater] No update found (silent check)")
            NSApp.dockTile.badgeLabel = nil
            clearUpdateNotification()
            return
        }

        if AppUpdater.shared.downloadState == .downloaded {
            sendUpdateNotification()
        } else if !AppUpdater.shared.automaticallyDownloadsUpdates {
            Logfile.app.info("[Updater] New update found (silent check)")
            sendUpdateNotification()
        }
    }
}

extension Notification.Name {
    static let appLockerPendingUpdateDidChange = Notification.Name("appLockerPendingUpdateDidChange")
}
