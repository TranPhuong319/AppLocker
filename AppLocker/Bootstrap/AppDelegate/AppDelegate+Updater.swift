//
//  AppDelegate+Updater.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import Sparkle
import UserNotifications
import AppKit

extension AppDelegate: AppUpdaterBridgeDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func didFindUpdate(_ item: SUAppcastItem) {
        guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              item.displayVersionString.compare(current, options: .numeric) == .orderedDescending
        else {
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            Logfile.core.debug("Update \(item.displayVersionString) is not newer than current \(currentVersion)")
            return
        }

        pendingUpdate = item

        let content = UNMutableNotificationContent()
        content.title = "AppLocker Update Available".localized
        content.body = "Version %@ is ready".localized(with: item.displayVersionString)
        content.sound = UNNotificationSound.defaultCritical
        content.badge = nil

        // EN: Use a fixed identifier to remove the correct notification when tapped.
        // VI: Dùng định danh cố định để xoá đúng thông báo khi người dùng bấm.
        let request = UNNotificationRequest(
            identifier: notificationIndentifiers,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func didNotFindUpdate() {
        Logfile.core.debug("No update found (silent check)")
        pendingUpdate = nil
        NSApp.dockTile.badgeLabel = nil
        UNUserNotificationCenter.current().setBadgeCount(0)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationIndentifiers])
    }
}
