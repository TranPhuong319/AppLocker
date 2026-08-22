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
            NSApp.activate()
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        if #available(macOS 14.0, *) {
            hostingController.sceneBridgingOptions = [.toolbars, .title]
        }

        var config = WindowConfiguration()
        config.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        config.titlebarAppearsTransparent = true
        config.titleVisibility = .hidden
        config.isOpaque = true
        config.backgroundColor = .windowBackgroundColor
        config.minSize = NSSize(width: 640, height: 440)

        let window = WindowManager.createWindow(contentViewController: hostingController, configuration: config)
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        window.toolbar = toolbar

        let controller = SettingsWindowController(window: window)
        window.delegate = controller
        shared = controller

        window.setContentSize(NSSize(width: 640, height: 440))
        window.minSize = NSSize(width: 640, height: 440)
        window.center()

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.shared = nil
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        var size = frameSize
        if size.width < 640 { size.width = 640 }
        if size.height < 440 { size.height = 440 }
        return size
    }
}
