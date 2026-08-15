//
//  AppDelegate+Actions.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit
import Foundation
import ServiceManagement

@MainActor
extension AppDelegate {
    @objc func openListApp() {
        guard ExtensionInstaller.shared.isInstalled else {
            NSApp.activate(ignoringOtherApps: true)
            let result = AlertShow.show(
                title: String(localized: "System Extension Required"),
                message: String(
                    localized: "AppLocker requires its Endpoint Security extension to be enabled in System Settings to manage applications."
                ),
                style: .warning,
                buttons: [
                    String(localized: "Open System Settings"),
                    String(localized: "Cancel")
                ],
                cancelIndex: 1,
                defaultIndex: 0
            )
            if case .button(let index, _) = result, index == 0 {
                SMAppService.openSystemSettingsLoginItems()
                ExtensionInstaller.shared.install()
            }
            return
        }

        AuthenticationManager.authenticate(
            reason: String(localized: "authenticate to open the application list")
        ) { success, error in
            if success {
                AppListWindowController.show()
                Logfile.core.debug("Opened AppList")
            } else {
                Logfile.core.error(
                    "Error opening list app: \(error as NSObject?)")
            }
        }
    }

    @objc func openSystemSettingsForExtension() {
        SMAppService.openSystemSettingsLoginItems()
        ExtensionInstaller.shared.install()
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.show()
    }

    @objc func uninstall() {
        Logfile.core.debug("Uninstall Clicked")
        NSApp.activate(ignoringOtherApps: true)

        let uninstallConfirmation = AlertShow.show(
            title: String(localized: "Uninstall AppLocker") + "?",
            message: String(localized: """
                You are about to uninstall AppLocker. Please make sure that all apps are unlocked!

                Your Mac will restart after Successful Uninstall
                """),
            style: .critical,
            buttons: [String(localized: "Uninstall"), String(localized: "Cancel")],
            cancelIndex: 1,
            destructiveIndex: 0,
            defaultIndex: 1
        )

        if case .button(index: 0, title: String(localized: "Uninstall")) = uninstallConfirmation {
            performUninstall()
        }
    }

    @objc func resetApp() {
        Logfile.core.debug("Reset App Clicked")
        NSApp.activate(ignoringOtherApps: true)
        let resetConfirmation = AlertShow.show(
            title: String(localized: "Reset AppLocker"),
            message: String(localized: """
                This operation will delete all settings including the list of locked applications. \
                After successful reset, the application will be reopened.

                Do you want to continue?
                """),
            style: .critical,
            buttons: [String(localized: "Reset"), String(localized: "Cancel")],
            cancelIndex: 1,
            destructiveIndex: 0,
            defaultIndex: 1
        )

        if case .button(index: 0, title: String(localized: "Reset")) = resetConfirmation {
            AuthenticationManager.authenticate(
                reason: String(localized: "authenticate to reset AppLocker")
            ) { [weak self] success, error in
                if success {
                    self?.performReset()
                } else if let error = error {
                    Logfile.core.error("Authentication failed for reset: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc func checkUpdate() {
        AppUpdater.shared.manualCheckForUpdates()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.bringFrontmostWindow(matching: "SU") // SPUpdater or SUUpdater
        }
    }

    @objc func about() {
        AboutWindowController.show()
    }

    // MARK: - Helper Methods

    private func performUninstall() {
        ExtensionInstaller.shared.uninstall { result in
            switch result {
            case .success:
                ESXPCClient.shared.authorizeShutdown(true) { _ in
                    DispatchQueue.main.async {
                        self.manageAgent(plistName: plistName, action: .uninstall)
                        self.removeConfig()
                        self.selfRemoveApp()
                        self.showRestartSheet()
                        NSApp.terminate(nil)
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    Logfile.core.error("[Uninstall] Failed to deactivate system extension: \(error.localizedDescription)")
                    AlertShow.showInfo(
                        title: String(localized: "System Extension Uninstallation Failed"),
                        message: error.localizedDescription,
                        style: .critical
                    )
                }
            }
        }
    }

    private func performReset() {
        removeConfig()
        restartApp()
    }

    private func bringFrontmostWindow(matching namePart: String) {
        for window in NSApp.windows {
            let windowClassName = String(describing: type(of: window))
            if windowClassName.contains(namePart) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                if namePart == "About" { window.makeKey() }
            }
        }
    }
}
