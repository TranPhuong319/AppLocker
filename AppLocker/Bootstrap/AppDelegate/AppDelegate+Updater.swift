//
//  AppDelegate+Updater.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit

extension AppDelegate: AppUpdaterBridgeDelegate {
    func didFindUpdate() {
        // Only notify immediately if we are NOT automatically downloading updates in the background.
        // If we are auto-downloading, we wait for didDownloadUpdate to show the "Ready to Install" notification.
        if !AppUpdater.shared.automaticallyDownloadsUpdates {
            Logfile.app.info("[Updater] New update found (silent check)")
            sendUpdateNotification()
        }
    }

    func didDownloadUpdate() {
        sendUpdateNotification()
    }

    func didNotFindUpdate() {
        Logfile.app.debug("[Updater] No update found (silent check)")
        NSApp.dockTile.badgeLabel = nil
        clearUpdateNotification()
    }
}

extension Notification.Name {
    static let appLockerPendingUpdateDidChange = Notification.Name("appLockerPendingUpdateDidChange")
}
