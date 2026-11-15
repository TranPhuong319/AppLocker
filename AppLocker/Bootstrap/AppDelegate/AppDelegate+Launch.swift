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
        Logfile.app.debug("[Launch] Bootstrapping LockES domain core service...")
        LockES.shared.bootstrap()

        Logfile.app.debug("[Launch] Starting AppScannerService...")
        AppScannerService.shared.start()

        Logfile.app.debug("[Launch] Starting UI components on app launch...")
        AuthCoordinator.shared.configureUIDependencies()
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
        self.menuBarController.setup(appearance: currentThemeAppearance)
        self.setupUpdateObserver()
        AppUpdater.shared.startTestAutoCheck()

        self.setupNotifications()

        Logfile.app.debug("[Launch] Setting up hotkey manager...")
        self.hotkey = HotKeyManager()

        registerSleepAndLockObservers()
    }

    @MainActor
    private func registerSleepAndLockObservers() {
        let workspaceEvents: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification
        ]
        for eventName in workspaceEvents {
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: eventName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleWorkspaceSleep()
                }
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWorkspaceSleep()
            }
        }
    }

    @MainActor
    private func handleWorkspaceSleep() {
        AuthCoordinator.shared.resetGracePeriods()
        let wasDisabled = LockES.shared.isProtectionDisabled
        let timeoutMinutes = LockES.shared.autoLockTimeoutMinutes
        Logfile.app.info(
            """
            [Launch] System sleep/lock event detected (autoLockTimeoutMinutes = \(timeoutMinutes), \
            wasProtectionDisabled = \(wasDisabled)).
            """
        )
        if wasDisabled {
            LockES.shared.setProtectionDisabled(false)
        }
    }
}
