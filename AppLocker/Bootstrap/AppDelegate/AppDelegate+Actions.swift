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
    @objc func openAppList() {
        guard ExtensionInstaller.shared.isInstalled else {
            NSApp.activate()
            let result = AlertShow.show(
                title: String(localized: "System Extension Required"),
                message: String(
                    localized: """
                    AppLocker requires its Endpoint Security extension to be enabled in \
                    System Settings to manage applications.
                    """
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
                openSystemSettingsForExtension()
            }
            return
        }

        Task { @MainActor in
            do {
                let success = try await AuthenticationManager.authenticate(
                    reason: String(localized: "authenticate to open the application list")
                )
                if success {
                    AppListWindowController.show()
                    Logfile.app.debug("[Actions] Opened AppList")
                }
            } catch {
                Logfile.app.error(
                    "[Actions] Error opening list app: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @objc func openSystemSettingsForExtension() {
        SMAppService.openSystemSettingsLoginItems()
        ExtensionInstaller.shared.install()
    }

    @objc func resumeProtection() {
        guard AppState.shared.manager.isProtectionDisabled else { return }
        AppState.shared.manager.setProtectionDisabled(false)
        Logfile.app.notice("[Actions] Protection resumed by user")
    }

    @objc func openSettings() {
        NSApp.activate()
        SettingsWindowController.show()
    }

    @objc func uninstall() {
        Logfile.app.debug("[Actions] Uninstall Clicked")
        NSApp.activate()

        let uninstallConfirmation = AlertShow.show(
            title: String(localized: "Uninstall AppLocker"),
            message: String(localized: """
                You are about to uninstall AppLocker. This action will delete application locking preferences \
                for all users on this Mac.

                Do you want to continue?
                """),
            style: .critical,
            buttons: [String(localized: "Uninstall"), String(localized: "Cancel")],
            cancelIndex: 1,
            defaultIndex: 1
        )

        if case .button(index: 0, _) = uninstallConfirmation {
            performUninstall()
        }
    }

    @objc func resetApp() {
        Logfile.app.debug("[Actions] Reset App Clicked")
        NSApp.activate()
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
            defaultIndex: 1
        )

        guard case .button(index: 0, _) = resetConfirmation else { return }

        Task { @MainActor [weak self] in
            do {
                let success = try await AuthenticationManager.authenticate(
                    reason: String(localized: "authenticate to reset AppLocker")
                )
                if success {
                    self?.performReset()
                }
            } catch {
                Logfile.app.error(
                    "[Actions] Authentication failed for reset: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    @objc func checkForUpdates() {
        AppUpdater.shared.checkForUpdates()
        NSApp.activate()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.bringFrontmostWindow(matching: "SU") // SPUpdater or SUUpdater
        }
    }

    @objc func showAboutWindow() {
        AboutWindowController.show()
    }

    // MARK: - Helper Methods

    private func performUninstall() {
        Task { [weak self] in
            let uninstallResult = await withCheckedContinuation { continuation in
                ExtensionInstaller.shared.uninstall { result in
                    continuation.resume(returning: result)
                }
            }
            guard let self else { return }

            switch uninstallResult {
            case .success:
                ESXPCClient.shared.disconnect()

                self.manageAgent(action: .uninstall)
                let configRemoved = self.removeConfig(purgeAll: true)
                let appRemoved = await self.selfRemoveApp()

                if configRemoved && appRemoved {
                    NSApp.terminate(nil)
                } else {
                    AlertShow.showInfo(
                        title: String(localized: "Uninstallation Incomplete"),
                        message: String(
                            localized: "Could not completely remove application files or configuration."
                        ),
                        style: .warning
                    )
                }
            case .failure(let error):
                Logfile.app.error(
                    "[Actions] Failed to deactivate system extension: \(error.localizedDescription)"
                )
                AlertShow.showInfo(
                    title: String(localized: "System Extension Uninstallation Failed"),
                    message: error.localizedDescription,
                    style: .critical
                )
            }
        }
    }

    private func performReset() {
        _ = removeConfig(purgeAll: false)
        restartApp()
    }

    private func bringFrontmostWindow(matching namePart: String) {
        for window in NSApp.windows {
            let windowClassName = String(describing: type(of: window))
            if windowClassName.contains(namePart) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
}
