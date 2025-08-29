//
//  AppDelegate.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//

import AppKit
import LocalAuthentication
import Security
import ServiceManagement
import Foundation
import SwiftUI

enum LoginAction {
    case none      // Only check status
    case install   // Install the helper tool
    case uninstall // Uninstall the helper tool
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSXPCListenerDelegate {
    var statusItem: NSStatusItem?
    var xpcListener: NSXPCListener?
    var connection: NSXPCConnection?
    let helperIdentifier = "com.TranPhuong319.AppLockerHelper"

    func isRunningAsAdmin() -> Bool {
        return getuid() == 0
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logfile.core.debug("Loading Application")

        HelperInstaller.checkAndAlertBlocking(helperToolIdentifier: helperIdentifier)

        // Setup menu bar
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        statusItem?.button?.image = NSImage(
            systemSymbolName: "lock.fill",
            accessibilityDescription: "AppLocker"
        )

        // Tạo menu rỗng và set delegate
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        _ = AppUpdater.shared
    }

    @objc func openListApp() {
        AuthenticationManager.authenticate(
            reason: "authenticate to open the application list".localized
        ) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    AppListWindowController.show()
                    Logfile.core.debug("Opened AppList")
                } else {
                    Logfile.core.error("Error when opening list app: \(errorMessage as NSObject?, privacy: .public)")
                }
            }
        }
    }

    @objc func quitApp() {
        AuthenticationManager.authenticate(reason: "quit application".localized) { success, errorMessage in
            if success {
                Logfile.core.debug("Quit Application")
                NSApp.terminate(nil)
            } else {
                Logfile.core.error("Error when escaping: \(errorMessage as NSObject?, privacy: .public)")
            }
        }
    }

    @objc func openSettings() {
        Logfile.core.info("Settings Clicked")
        SettingsWindowController.show()
    }

    @objc func uninstall() {
        Logfile.core.info("Uninstall Clicked")
    }

    @objc func checkUpdate() {
        Logfile.core.info("CheckUpdate Clicked")

        // Lấy update channel từ UserDefaults
        let savedChannel = UserDefaults.standard.string(forKey: "updateChannel") ?? "Stable"
        let useBeta = (savedChannel == "Beta")

        // Gọi check update thủ công
        AppUpdater.shared.checkForUpdates(useBeta: useBeta)

        // Kích hoạt app lên foreground
        NSApp.activate(ignoringOtherApps: true)

        // Delay tí để Sparkle kịp tạo cửa sổ
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in NSApp.windows {
                let windowClass = String(describing: type(of: window))
                if windowClass.contains("SU") || windowClass.contains("SPU") {
                    window.makeKeyAndOrderFront(nil) // đem lên trước
                    window.orderFrontRegardless()     // ép ra trên cùng
                }
            }
        }
    }


    @objc func launchAtLogin(_ sender: NSMenuItem) {
        Task {
            let loginItem = SMAppService.mainApp

            if sender.state == .on {
                do {
                    try await loginItem.unregister()
                    sender.state = .off
                } catch {
                    Logfile.core.error("❌ Unregister failed: \(error, privacy: .public)")
                }
            } else {
                do {
                    try loginItem.register()
                    sender.state = .on
                } catch {
                    Logfile.core.error("❌ Register failed: \(error, privacy: .public)")
                }
            }
        }
    }

    @objc func about() {
        Logfile.core.info("About Clicked")

        // Hiển thị About panel
        NSApp.orderFrontStandardAboutPanel(nil)

        // Kích hoạt app lên foreground và ép cửa sổ About lên trên cùng
        NSApp.activate(ignoringOtherApps: true)

        // Delay tí để About panel kịp tạo cửa sổ
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                let windowClass = String(describing: type(of: window))
                if windowClass.contains("About") {
                    window.makeKeyAndOrderFront(nil)   // đưa lên trước
                    window.orderFrontRegardless()      // ép ra trên cùng
                }
            }
        }
    }

    // Hàm này chạy mỗi khi user click mở menu
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if NSEvent.modifierFlags.contains(.option) {
            // Menu khi giữ Option
            menu.addItem(NSMenuItem(
                title: "Settings".localized,
                action: #selector(openSettings),
                keyEquivalent: ""
            ))
            menu.addItem(NSMenuItem.separator())
            let launchItem = NSMenuItem(
                title: "Launch At Login".localized,
                action: #selector(launchAtLogin),
                keyEquivalent: ""
            )
            launchItem.target = self

            let status = SMAppService.mainApp.status
            launchItem.state = (status == .enabled) ? .on : .off
            menu.addItem(launchItem)
            menu.addItem(NSMenuItem(
                title: "Check for Updates...".localized,
                action: #selector(checkUpdate),
                keyEquivalent: ""
            ))
            menu.addItem(NSMenuItem(
                title: "About AppLocker".localized,
                action: #selector(about),
                keyEquivalent: ""
            ))
            #if DEBUG
                menu.addItem(NSMenuItem.separator())
                menu.addItem(NSMenuItem(
                    title: "Uninstall AppLocker".localized,
                    action: #selector(uninstall),
                    keyEquivalent: ""
                ))
            #endif
        } else {
            // Menu bình thường
            menu.addItem(NSMenuItem(
                title: "Manage the application list".localized,
                action: #selector(openListApp),
                keyEquivalent: "s"
            ))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(
                title: "Quit AppLocker".localized,
                action: #selector(quitApp),
                keyEquivalent: "q"
            ))
        }
    }
}
