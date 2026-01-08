//
//  AppDelegate+Notifications.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import UserNotifications

extension AppDelegate {
    func buildUpdateNotification() -> UNNotificationRequest {
        let updater = AppUpdater.shared.delegate
        let content = UNMutableNotificationContent()

        switch (updater.channel, updater.downloadState) {

        // 1. Stable – chưa tải
        case (.stable, .notDownloaded):
            content.title = String(localized: "Update Available")
            content.body  = String(localized: "A new stable version is available. Do you want to update?")

        // 2. Stable – đã tải
        case (.stable, .downloaded):
            content.title = String(localized: "Ready to Install")
            content.body  = String(localized: "The update has been downloaded. Install now?")

        // 3. Beta – chưa tải
        case (.beta, .notDownloaded):
            content.title = String(localized: "Beta Update Available")
            content.body  = String(localized: "A new beta version is available. Do you want to update?")

        // 4. Beta – đã tải
        case (.beta, .downloaded):
            content.title = String(localized: "Beta Ready to Install")
            content.body  = String(localized: "The beta update has been downloaded. Install now?")
        }

        content.categoryIdentifier = "SPARKLE_UPDATE"
        content.sound = .default

        return UNNotificationRequest(
            identifier: notificationIndentifiers,
            content: content,
            trigger: nil
        )
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {

        if response.actionIdentifier == UpdateNotificationAction.more ||
           response.actionIdentifier == UNNotificationDefaultActionIdentifier {

            AppUpdater.shared.updaterController.checkForUpdates(nil)
        }

        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [notificationIndentifiers])

        completionHandler()
    }
}
