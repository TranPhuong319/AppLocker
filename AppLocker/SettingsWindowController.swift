//
//  SettingsWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import AppKit
import SwiftUI

class SettingsWindowController: NSObject, NSWindowDelegate {
    static var shared: NSPanel?

    static func show() {
        if let panel = shared {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ContentView()
        let hosting = NSHostingView(rootView: contentView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )

        panel.title = "AppLocker Settings"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = hosting
        panel.center()

        // Set delegate to detect losing focus
        let controller = SettingsWindowController()
        panel.delegate = controller

        shared = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Kiểm tra nếu còn bất kỳ cửa sổ nào thuộc app đang là keyWindow thì không đóng
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasKeyWindowInApp = NSApp.windows.contains(where: { $0.isKeyWindow })

            if !hasKeyWindowInApp {
                if let panel = SettingsWindowController.shared {
                    panel.close()
                    SettingsWindowController.shared = nil
                }
            }
        }
    }
}
