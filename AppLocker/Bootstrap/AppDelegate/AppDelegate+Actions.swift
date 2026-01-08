//
//  AppDelegate+Actions.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import Foundation
import AppKit
import ServiceManagement

extension AppDelegate {
    @objc func openListApp() {
        AuthenticationManager.authenticate(
            reason: String(localized: "authenticate to open the application list")
        ) { success, error in
            DispatchQueue.main.async {
                if success {
                    AppListWindowController.show()
                    Logfile.core.debug("Opened AppList")
                } else {
                    Logfile.core.error(
                        "Error opening list app: \(error as NSObject?, privacy: .public)"
                    )
                }
            }
        }
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.show()
    }

    @objc func uninstall() {
        Logfile.core.info("Uninstall Clicked")
        let manager = AppState.shared.manager
        NSApp.activate(ignoringOtherApps: true)

        if manager.lockedApps.isEmpty || modeLock == .es {
            let confirm = AlertShow.show(
                title: String(localized: "Uninstall Applocker?"),
                message:
                    String(localized: """
                    You are about to uninstall AppLocker. \
                    Please make sure that all apps are unlocked!

                    Your Mac will restart after Successful Uninstall
                    """),
                style: .critical,
                buttons: [
                    String(localized: "Cancel"),
                    String(localized: "Uninstall")
                ],
                cancelIndex: 0
            )

            switch confirm {
            case .button(index: 1, title: String(localized: "Uninstall")):
                switch modeLock {
                case .es:
                    ExtensionInstaller.shared.onUninstalled = {
                        self.manageAgent(plistName: plistName, action: .uninstall)
                        self.removeConfig()
                        self.selfRemoveApp()
                        self.showRestartSheet()
                        NSApp.terminate(nil)
                    }
                    ExtensionInstaller.shared.uninstall()
                case .launcher:
                    AuthenticationManager.authenticate(
                        reason: String(localized: "uninstall the application")
                    ) { success, _ in
                        DispatchQueue.main.async {
                            if success {
                                self.callUninstallHelper()
                                let loginItem = SMAppService.mainApp
                                let status = loginItem.status
                                if status == .enabled {
                                    try? loginItem.unregister()
                                }
                                _ = HelperInstaller.manageHelperTool(
                                    action: .uninstall,
                                    helperToolIdentifier: self.helperIdentifier
                                )
                                self.selfRemoveApp()
                                self.removeConfig()
                                self.showRestartSheet()
                                NSApp.terminate(nil)
                            }
                        }
                    }
                case nil:
                    break
                }
            case .cancelled:
                break
            default:
                break
            }
        } else {
            AlertShow.showInfo(
                title: String(localized: "Unable to uninstall AppLocker"),
                message: String(
                    localized: "You need to unlock all applications before Uninstalling"
                ),
                style: .critical
            )
        }
    }

    @objc func resetApp() {
        Logfile.core.info("Reset App Clicked")
        NSApp.activate(ignoringOtherApps: true)
        let confirm = AlertShow.show(
            title: String(localized: "Reset AppLocker"),
            message:
            String(localized: """
            This operation will delete all settings including the list of locked applications. \
            After successful reset, the application will be reopened.

            Do you want to continue?
            """),
            style: .critical,
            buttons: [
                String(localized: "Cancel"),
                String(localized: "Reset")
            ],
            cancelIndex: 0
        )

        switch confirm {
        case .button(index: 1, title: String(localized: "Reset")):
            switch modeLock {
            case .launcher:
                let loginItem = SMAppService.mainApp
                let status = loginItem.status
                if status == .enabled {
                    try? loginItem.unregister()
                }
                removeConfig()
                _ = HelperInstaller.manageHelperTool(
                    action: .uninstall, helperToolIdentifier: helperIdentifier
                )
                restartApp(mode: nil)
            case .es:
                ExtensionInstaller.shared.onUninstalled = {
                    self.removeConfig()
                    self.manageAgent(plistName: plistName, action: .uninstall)
                    modeLock = nil
                    self.restartApp(mode: modeLock)
                }
                ExtensionInstaller.shared.uninstall()
            case nil:
                break
            }

        default:
            break
        }
    }

    @objc func checkUpdate() {
        AppUpdater.shared.manualCheckForUpdates()

        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in NSApp.windows {
                let cls = String(describing: type(of: window))
                if cls.contains("SU") || cls.contains("SPU") {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }

    @objc func launchAtLogin(_ sender: NSMenuItem) {
        Task {
            let loginItem = SMAppService.mainApp
            if sender.state == .on {
                try? await loginItem.unregister()
                sender.state = .off
            } else {
                try? loginItem.register()
                sender.state = .on
            }
        }
    }

    @objc func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                let cls = String(describing: type(of: window))
                if cls.contains("About") {
                    window.makeKey()
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }
}
