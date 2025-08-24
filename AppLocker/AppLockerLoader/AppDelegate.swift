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

class AppDelegate: NSObject, NSApplicationDelegate, NSXPCListenerDelegate {
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "AppLocker")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Manage the application list".localized, action: #selector(openSettings), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit AppLocker".localized, action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func openSettings() {
        AuthenticationManager.authenticate(reason: "authenticate to open the application list".localized) { success, errorMessage in
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
                Task{
                    await self.manageHelperTool(action: .uninstall)
                }
                Logfile.core.info("Uninstall Successfully")
                Logfile.core.debug("Quit Application")
                NSApp.terminate(nil)
            } else {
                Logfile.core.error("Error when escaping: \(errorMessage as NSObject?, privacy: .public)")
            }
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

