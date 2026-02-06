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
            setupUIComponents()
        } else if config == .esMode {
            ExtensionInstaller.shared.onInstalled = {
                Logfile.core.log("[App] Setting up UI after extension install")
                self.setupUIComponents()
            }
            Logfile.core.log("Installing Endpoint Security extension...")
            ExtensionInstaller.shared.install()
        }
    }

    func setupUIComponents() {
        Logfile.core.info("Starting menu bar and Notification")
        self.setupMenuBar()

        AppUpdater.shared.setBridgeDelegate(self)
        AppUpdater.shared.startTestAutoCheck()

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.badge, .sound, .alert]) { _, error in
                if let error = error {
                    Logfile.core.error("Notification error: \(error)")
                }
            }


        Logfile.core.log("Setting up hotkey manager...")
        self.hotkey = HotKeyManager()

        Logfile.core.log("Setting up Touch Bar...")
        if let window = NSApp.windows.first {
            TouchBarManager.shared.apply(to: window, type: .mainWindow)
        }
    }
}
