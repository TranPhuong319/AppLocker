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

        // Setup menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "AppLocker")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Application_list_management".localized, action: #selector(openSettings), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Escape_Applocker".localized, action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func openSettings() {
        AuthenticationManager.authenticate(reason: "Authentication_to_open_the_application_list".localized) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    AppListWindowController.show()
                }
            }
        }
    }

    @objc func quitApp() {
        AuthenticationManager.authenticate(reason: "Application_escape".localized) { success, errorMessage in
            if success {
                NSApp.terminate(nil)
            }
        }
    }
}


