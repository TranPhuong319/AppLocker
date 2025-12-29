//
//  AppDelegate+Notifications.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import UserNotifications

extension AppDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == notificationIndentifiers {
            // EN: Open Sparkle update window.
            // VI: Mở cửa sổ cập nhật của Sparkle.
            AppUpdater.shared.updaterController.checkForUpdates(nil)
            // EN: Clear the delivered notification.
            // VI: Xoá thông báo đã gửi.
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [notificationIndentifiers]
            )
        }
        completionHandler()
    }
}
