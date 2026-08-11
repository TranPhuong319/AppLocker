//
//  AppDelegate+Updater.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit
import Sparkle
import UserNotifications

extension AppDelegate: AppUpdaterBridgeDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { false }

    func didFindUpdate(_ item: SUAppcastItem) {
        pendingUpdate = item
        NotificationCenter.default.post(name: .appLockerPendingUpdateDidChange, object: nil)

        // Only notify immediately if we are NOT automatically downloading updates in the background.
        // If we are auto-downloading, we wait for didDownloadUpdate to show the "Ready to Install" notification.
        if !AppUpdater.shared.updaterController.updater.automaticallyDownloadsUpdates {
            Logfile.core.debug("New update found! (silent check)")
            let request = buildUpdateNotification()
            UNUserNotificationCenter.current().add(request)
        }
    }

    func didDownloadUpdate() {
        let request = buildUpdateNotification()
        UNUserNotificationCenter.current().add(request)
    }

    func didNotFindUpdate() {
        Logfile.core.debug("No update found (silent check)")
        pendingUpdate = nil
        NotificationCenter.default.post(name: .appLockerPendingUpdateDidChange, object: nil)
        NSApp.dockTile.badgeLabel = nil
        UNUserNotificationCenter.current().setBadgeCount(0)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [
            notificationIndentifiers
        ])
    }
}

extension Notification.Name {
    static let appLockerPendingUpdateDidChange = Notification.Name("appLockerPendingUpdateDidChange")
}
