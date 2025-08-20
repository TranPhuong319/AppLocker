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

class AppDelegate: NSObject, NSApplicationDelegate, NSXPCListenerDelegate {
    var statusItem: NSStatusItem?
    var xpcListener: NSXPCListener?
    var connection: NSXPCConnection?
    
    func isRunningAsAdmin() -> Bool {
        return getuid() == 0
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logfile.core.debug("Loading Application")
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
                NSApp.terminate(nil)
                Logfile.core.debug("Application quited")
            } else {
                Logfile.core.error("Error when escaping: \(errorMessage as NSObject?, privacy: .public)")
            }
        }
    }
}


