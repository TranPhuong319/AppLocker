//
//  AppDelegate.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ẩn khỏi Dock và Force Quit
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "AppLocker")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit AppLocker", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu

        // Bắt đầu theo dõi app
        AppLockerController.shared.startMonitoring()
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc func quitApp() {
        guard AuthenticationManager.authenticate() else {
            print("Sai mật khẩu")
            return
        }
        NSApp.terminate(nil)
    }
}
