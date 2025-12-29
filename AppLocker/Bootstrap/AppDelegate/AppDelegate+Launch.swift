//
//  AppDelegate+Launch.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import UserNotifications
import AppKit

extension AppDelegate {
    func launchConfig(config: AppMode) {
        if config == .launcher {
            HelperInstaller.checkAndAlertBlocking(helperToolIdentifier: helperIdentifier)
        } else if config == .es {
            // EN: Register callback after the ES extension is installed.
            // VI: Đăng ký callback sau khi cài extension ES.
            ExtensionInstaller.shared.onInstalled = {
                Logfile.core.info("[App] Starting XPC server after extension install")
                XPCServer.shared.start()

                Logfile.core.info("Starting menu bar and Notification")
                self.setupMenuBar()

                AppUpdater.shared.setBridgeDelegate(self)
                AppUpdater.shared.startTestAutoCheck()

                UNUserNotificationCenter.current().delegate = self
                UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { _, error in
                    if let error = error { Logfile.core.error("Notification error: \(error, privacy: .public)") }
                }

                Logfile.core.info("Starting User state")
                SessionObserver.shared.start()

                Logfile.core.info("Setting up hotkey manager...")
                self.hotkey = HotKeyManager()

                Logfile.core.info("Setting up Touch Bar...")
                if let window = NSApp.windows.first {
                    TouchBarManager.shared.apply(to: window, type: .mainWindow)
                }
            }

            Logfile.core.info("Installing Endpoint Security extension...")
            ExtensionInstaller.shared.install()
        }
    }
}
