//
//  AppListWindowController.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//

import AppKit
import SwiftUI

class AppListWindowController: NSWindowController, NSWindowDelegate {
    static var shared: AppListWindowController?

    static func show() {
        if let controller = shared {
            Logfile.core.info("📂 AppListWindowController: Reusing existing window instance")
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ContentView()
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )

        window.minSize = NSSize(width: 420, height: 480)
        window.maxSize = NSSize(width: 420, height: 480)

        window.title = "Manage the application list".localized
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = nil

        let controller = AppListWindowController(window: window)
        window.delegate = controller
        shared = controller

        Logfile.core.info("📂 AppListWindowController: New window instance created")

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        Logfile.core.info("📂 AppListWindowController: Window shown and app activated")
    }

    func windowWillClose(_ notification: Notification) {
        Logfile.core.info("📂 AppListWindowController: Window will close, clearing shared instance")
        AppListWindowController.shared = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        Logfile.core.info("📂 AppListWindowController: Window lost focus, scheduling auto-close check")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let stillHasKeyWindow = NSApp.windows.contains(where: { $0.isKeyWindow })
            if !stillHasKeyWindow {
                Logfile.core.info("📂 AppListWindowController: No key window found, closing window")
                self.close()
            } else {
                Logfile.core.debug("📂 AppListWindowController: Another key window still active, keeping window open")
            }
        }
    }
}
