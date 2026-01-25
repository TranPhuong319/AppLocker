//
//  AppDelegate+Actions.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit
import Foundation
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
                    Logfile.core.pError(
                        "Error opening list app: \(error as NSObject?)")
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
        let lockManager = AppState.shared.manager
        NSApp.activate(ignoringOtherApps: true)

        if lockManager.lockedApps.isEmpty || modeLock == .es {
            let uninstallConfirmation = AlertShow.show(
                title: String(localized: "Uninstall Applocker?"),
                message:
                    String(
                        localized: """
                            You are about to uninstall AppLocker. \
                            Please make sure that all apps are unlocked!

                            Your Mac will restart after Successful Uninstall
                            """),
                style: .critical,
                buttons: [
                    String(localized: "Uninstall"),
                    String(localized: "Cancel")
                ],
                cancelIndex: 1
            )

            switch uninstallConfirmation {
            case .button(index: 0, title: String(localized: "Uninstall")):
                switch modeLock {
                case .es:
                    ExtensionInstaller.shared.onUninstalled = {
                        self.manageAgent(plistName: plistName, action: .uninstall)
                        self.manageHelperLoginItem(
                            helperBundleID: loginItem,
                            action: .uninstall
                        )
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
        let resetConfirmation = AlertShow.show(
            title: String(localized: "Reset AppLocker"),
            message:
                String(
                    localized: """
                        This operation will delete all settings including the list of locked applications. \
                        After successful reset, the application will be reopened.

                        Do you want to continue?
                        """),
            style: .critical,
            buttons: [
                String(localized: "Reset"),
                String(localized: "Cancel")
            ],
            cancelIndex: 1
        )

        switch resetConfirmation {
        case .button(index: 0, title: String(localized: "Reset")):
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
                    self.manageHelperLoginItem(
                        helperBundleID: loginItem,
                        action: .uninstall
                    )
                    // Call restartApp first, then uninstall agent in the completion handler
                    // This ensures the new app is launched before the current one is killed by agent uninstallation
                    self.restartApp(mode: nil) {
                        self.manageAgent(plistName: plistName, action: .uninstall)
                    }
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
                let windowClassName = String(describing: type(of: window))
                if windowClassName.contains("SU") || windowClassName.contains("SPU") {
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
                let windowClassName = String(describing: type(of: window))
                if windowClassName.contains("About") {
                    window.makeKey()
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }
}
