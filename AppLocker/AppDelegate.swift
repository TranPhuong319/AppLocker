//
//  AppDelegate.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import AppKit
import LocalAuthentication
import Security
import ServiceManagement
import Foundation


class AppDelegate: NSObject, NSApplicationDelegate, NSXPCListenerDelegate {
    var statusItem: NSStatusItem?
    var xpcListener: NSXPCListener?
    var connection: NSXPCConnection?
    
    func isRunningAsAdmin() -> Bool {
        return getuid() == 0
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(["vi"], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        // Ẩn khỏi Dock và Force Quit
//        NSApp.setActivationPolicy(.accessory)
        if let mainMenu = NSApp.mainMenu,
           let appMenu = mainMenu.items.first?.submenu {

            if let settingsItem = appMenu.items.first(where: { $0.title == "Settings…" || $0.title == "Cài đặt…" }) {
                settingsItem.target = self
                settingsItem.action = #selector(openSettings)
            }

            if let settingsItem = appMenu.items.first(where: { $0.title == "Quit AppLocker" || $0.title == "Thoát AppLocker" }) {
                settingsItem.target = self
                settingsItem.action = #selector(quitApp)
            }
        }


        // Setup menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "AppLocker")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Cài đặt", action: #selector(openSettings), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Thoát AppLocker", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func openSettings() {
        AuthenticationManager.authenticate(reason: "xác thực để mở Cài đặt") { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    SettingsWindowController.show()
                }
            }
        }
    }

    @objc func quitApp() {
        AuthenticationManager.authenticate(reason: "thoát ứng dụng") { success, errorMessage in
            if success {
                NSApp.terminate(nil)
            }
        }
    }
}


