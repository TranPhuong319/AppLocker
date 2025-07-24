//
//  AppDelegate.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import AppKit
import LocalAuthentication
import Security

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    
    func isRunningAsAdmin() -> Bool {
        return getuid() == 0
    }

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
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "xác thực để mở Cài đặt") { success, error in
                DispatchQueue.main.async {
                    if success {
                        SettingsWindowController.show()
                    } else {
                        NSSound.beep()
                        print("Xác thực thất bại: \(error?.localizedDescription ?? "Unknown error")")
                    }
                }
            }
        } else {
            // Nếu không dùng được Touch ID/Face ID, fallback về xác thực thủ công
            if AuthenticationManager.authenticate() {
                SettingsWindowController.show()
            } else {
                NSSound.beep()
                print("Sai mật khẩu")
            }
        }
    }


    @objc func quitApp() {
        guard AuthenticationManager.authenticate() else {
            print("Sai mật khẩu")
            return
        }
        NSApp.terminate(nil)
    }
}
