//
//  SettingsWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 26/8/25.
//

import SwiftUI
import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static var shared: SettingsWindowController?

    static func show() {
        if let controller = shared {
            controller.window?.center()
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())

        var config = WindowConfiguration()
        config.title = String(localized: "Settings")
        config.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        config.titlebarAppearsTransparent = true
        config.titleVisibility = .visible
        config.isOpaque = false
        config.backgroundColor = .clear

        let window = WindowManager.createWindow(contentViewController: hostingController, configuration: config)
        
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        let controller = SettingsWindowController(window: window)
        window.delegate = controller
        shared = controller

        window.setContentSize(NSSize(width: 640, height: 440))
        window.center()

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.shared = nil
    }
}
