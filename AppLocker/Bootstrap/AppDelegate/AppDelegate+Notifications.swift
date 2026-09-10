//
//  AppDelegate+Notifications.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit
import UserNotifications

extension AppDelegate: @MainActor UNUserNotificationCenterDelegate {
    private static let updateNotificationIdentifier = "AppLockerUpdateNotification"

    func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.badge, .sound, .alert]) { _, error in
            if let error = error {
                Logfile.app.error(
                    "[Notification] Authorization error: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

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
            identifier: Self.updateNotificationIdentifier,
            content: content,
            trigger: nil
        )
    }

    func sendUpdateNotification() {
        let request = buildUpdateNotification()
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                Logfile.app.error(
                    """
                    [Notification] Failed to schedule update notification: \
                    \(error.localizedDescription, privacy: .public)
                    """
                )
            }
        }
    }

    func clearUpdateNotification() {
        UNUserNotificationCenter.current().setBadgeCount(0)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [
            Self.updateNotificationIdentifier
        ])
    }

    func sendBlockedNotification(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Application Lock")
        content.body = String(format: String(localized: "%@ has been blocked from launching."), appName)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "BlockedAppNotification-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                Logfile.app.error(
                    """
                    [Notification] Failed to deliver blocked notification for \(appName, privacy: .public): \
                    \(error.localizedDescription, privacy: .public)
                    """
                )
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard response.notification.request.content.categoryIdentifier == "SPARKLE_UPDATE" else {
            return
        }

        if response.actionIdentifier == UpdateNotificationAction.more ||
           response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            checkForUpdates()
        }

        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [Self.updateNotificationIdentifier])
    }
}
