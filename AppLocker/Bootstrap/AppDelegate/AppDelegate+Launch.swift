//
//  AppDelegate+Launch.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit

extension AppDelegate {
    @MainActor
    func launchConfig() {
        Logfile.app.debug("[Launch] Starting UI components on app launch...")
        self.setupUIComponents()

        Logfile.app.debug("[Launch] Starting Call Services observer...")
        CallServiceObserver.shared.startMonitoring()

        Logfile.app.info("[Launch] Installing Endpoint Security extension...")
        ExtensionInstaller.shared.install { result in
            if case .success = result {
                Logfile.app.info("[Launch] Endpoint Security extension activated successfully.")
            }
        }
    }

    @MainActor
    func setupUIComponents() {
        Logfile.app.debug("[Launch] Starting menu bar and Notification setup")
        self.setupMenuBar()
        self.setupUpdateObserver()
        AppUpdater.shared.startTestAutoCheck()

        self.setupNotifications()

        Logfile.app.debug("[Launch] Setting up hotkey manager...")
        self.hotkey = HotKeyManager()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWorkspaceSleep()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWorkspaceSleep()
            }
        }
    }

    @objc
    @MainActor
    private func handleWorkspaceSleep() {
        XPCServer.shared.lastAuthTimestampsByPath.removeAll()
        let timeoutMinutes = AppState.shared.manager.autoLockTimeoutMinutes
        if timeoutMinutes != 0 {
            Logfile.app.info(
                """
                [Launch] Workspace sleep event detected (autoLockTimeoutMinutes = \(timeoutMinutes)). \
                Re-enabling application lock.
                """
            )
            AppState.shared.manager.setProtectionDisabled(false)
        }
    }
}
