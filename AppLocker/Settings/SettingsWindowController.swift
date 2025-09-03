//
//  SettingsWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 26/8/25.
//

import SwiftUI

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static var shared: SettingsWindowController?

    static func show() {
        if let controller = shared {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView()
        let hostingView = NSHostingView(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "Settings".localized
        window.setFrameAutosaveName("")   // không lưu vị trí cũ

        // Center theo visibleFrame (trừ menu bar + dock)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = window.frame.size
            let x = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        let controller = SettingsWindowController(window: window)
        window.delegate = controller
        shared = controller

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.shared = nil
    }
}
