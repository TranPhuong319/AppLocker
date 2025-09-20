//
//  SettingsWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 26/8/25.
//

import SwiftUI
import AppKit

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static var shared: SettingsWindowController?

    // Hiển thị cửa sổ settings
    static func show() {
        if let controller = shared {
            NSApp.activate(ignoringOtherApps: true)        // activate trước
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
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
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        let controller = SettingsWindowController(window: window)
        window.delegate = controller
        shared = controller

        // Bật app trước khi show
        NSApp.activate(ignoringOtherApps: true)

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async {
            window.center()
        }
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.shared = nil
    }
}
