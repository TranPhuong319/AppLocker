//
//  AppDelegate+Launch.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import UserNotifications
import AppKit

extension AppDelegate {
    @MainActor
    func launchConfig() {
        Logfile.core.info("Starting UI components on app launch...")
        self.setupUIComponents()

        Logfile.core.log("Installing Endpoint Security extension...")
        ExtensionInstaller.shared.install { result in
            if case .success = result {
                Logfile.core.log("[App] Endpoint Security extension activated successfully.")
            }
        }
    }

    @MainActor
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

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
    }

    @objc @MainActor private func handleWorkspaceSleep() {
        XPCServer.lastAuthTimestampsByPath.removeAll()
        let timeoutMinutes = UserDefaults.standard.integer(forKey: "autoLockTimeoutMinutes")
        if timeoutMinutes != 0 {
            Logfile.core.log("Workspace sleep event detected (autoLockTimeoutMinutes = \(timeoutMinutes)). Re-enabling application lock.")
            AppState.shared.manager.setProtectionDisabled(false)
        }
    }

    func launchedByLaunchd() -> Bool {
        guard let launchByLaunchctl = ProcessInfo.processInfo.environment[
            "LAUNCHED_BY_LAUNCHD"
        ] else {
            return false
        }
        return launchByLaunchctl == "1"
    }
}
