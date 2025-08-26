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

enum HelperToolAction {
    case none      // Only check status
    case install   // Install the helper tool
    case uninstall // Uninstall the helper tool
}

enum LoginAction {
    case none      // Only check status
    case install   // Install the helper tool
    case uninstall // Uninstall the helper tool
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSXPCListenerDelegate {
    var statusItem: NSStatusItem?
    var xpcListener: NSXPCListener?
    var connection: NSXPCConnection?
    let helperToolIdentifier = "com.TranPhuong319.AppLockerHelper"
    
    func isRunningAsAdmin() -> Bool {
        return getuid() == 0
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logfile.core.debug("Loading Application")
        
        Task {
            await manageHelperTool(action: .install)
        }
        
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
        AuthenticationManager.authenticate(reason: "authenticate to open the application list".localized) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    AppListWindowController.show()
                    Logfile.core.debug("Opened AppList")
                    AppUpdater.shared.gentleReminder()
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
    
    @objc func OpenSettings(){
        Logfile.core.info("Settings Clicked")
        SettingsWindowController.shared.show()
    }
    
    @objc func Uninstall(){
        Logfile.core.info("Uninstall Clicked")
    }
    
    @objc func CheckUpdate(){
        Logfile.core.info("CheckUpdate Clicked")
        // Gọi check update thủ công
        AppUpdater.shared.checkForUpdates()
    }
    @objc func LaunchAtLogin(_ sender: NSMenuItem) {
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

    @objc func About(){
        Logfile.core.info("About Clicked")
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    // Hàm này chạy mỗi khi user click mở menu
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if NSEvent.modifierFlags.contains(.option) {
            // Menu khi giữ Option
            menu.addItem(NSMenuItem(
                title: "Settings".localized,
                action: #selector(OpenSettings),
                keyEquivalent: ""
            ))
            menu.addItem(NSMenuItem.separator())
            // 👉 Launch At Login có tick
            let launchItem = NSMenuItem(
                title: "Launch At Login".localized,
                action: #selector(LaunchAtLogin),
                keyEquivalent: ""
            )
            launchItem.target = self

            let status = SMAppService.mainApp.status
            launchItem.state = (status == .enabled) ? .on : .off
            menu.addItem(launchItem)
            menu.addItem(NSMenuItem(
                title: "Check for Updates...".localized,
                action: #selector(CheckUpdate),
                keyEquivalent: ""
            ))
            menu.addItem(NSMenuItem(
                title: "About AppLocker".localized,
                action: #selector(About),
                keyEquivalent: ""
            ))
            #if DEBUG
                menu.addItem(NSMenuItem.separator())
                menu.addItem(NSMenuItem(
                    title: "Uninstall AppLocker".localized,
                    action: #selector(Uninstall),
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

    func manageHelperTool(action: HelperToolAction = .none) async {
        let plistName = "\(helperToolIdentifier).plist"
        let service = SMAppService.daemon(plistName: plistName)

        // Perform install/uninstall actions if specified
        switch action {
        case .install:
            // Pre-check before registering
            switch service.status {
            case .requiresApproval:
                Logfile.core.info("Registered but requires enabling in System Settings > Login Items.")
                SMAppService.openSystemSettingsLoginItems()
            case .enabled:
                Logfile.core.info("Service is already enabled.")
            default:
                do {
                    try service.register()
                    if service.status == .requiresApproval {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } catch let nsError as NSError {
                    if nsError.code == 1 { // Operation not permitted
                        Logfile.core.warning("Permission required. Enable in System Settings > Login Items.")
                        SMAppService.openSystemSettingsLoginItems()
                    } else {
                        Logfile.core.error("Installation failed: \(nsError.localizedDescription, privacy: .public)")
                        print("Failed to register helper: \(nsError.localizedDescription)")
                    }
                }
            }

        case .uninstall:
            do {
                try await service.unregister()
                service.unregister { error in
                    if let error {
                        print("❌ Unregister failed: \(error.localizedDescription)")
                    } else {
                        print("✅ Helper successfully unregistered")
                    }
                }
                // Close any existing connection
                connection?.invalidate()
                connection = nil
            } catch let nsError as NSError {
                Logfile.core.error("Failed to unregister helper: \(nsError.localizedDescription,privacy: .public)")
            }

        case .none:
            break
        }
    }
}

