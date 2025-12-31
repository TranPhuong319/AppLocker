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

    static func show() {
        if let controller = shared {
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView()
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)

        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.backingType = .buffered
        window.title = "Settings".localized
//        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.setContentSize(NSSize(width: 500, height: 400))
        window.center()

        let controller = SettingsWindowController(window: window)
        window.delegate = controller
        shared = controller

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        // Giải phóng bộ nhớ khi đóng cửa sổ
        SettingsWindowController.shared = nil
    }
}
