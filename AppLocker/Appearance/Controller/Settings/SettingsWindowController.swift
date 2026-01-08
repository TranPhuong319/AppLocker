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
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())

        let window = NSWindow(
            contentViewController: hostingController
        )
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.backingType = .buffered
        window.title = String(localized: "Settings")
        window.isReleasedWhenClosed = false

        let controller = SettingsWindowController(window: window)
        window.delegate = controller
        shared = controller

        controller.showWindow(nil)

        // Đảm bảo SwiftUI layout xong
        window.contentView?.layoutSubtreeIfNeeded()

        // Lấy size thật từ SwiftUI
        let fittingSize = hostingController.view.fittingSize
        window.setContentSize(fittingSize)

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.shared = nil
    }
}
