//
//  WelcomeWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import SwiftUI
import AppKit

class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    static var shared: WelcomeWindowController?

    static func show() {
        if let controller = shared {
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let contentView = WelcomeView()
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.backingType = .buffered
        window.title = "Welcome to AppLocker".localized
        window.titlebarAppearsTransparent = true // Làm thanh tiêu đề trong suốt
        window.titleVisibility = .hidden

        // 3. Thiết lập kích thước cố định
        let fixedSize = NSSize(width: 350, height: 450)
        window.setContentSize(fixedSize)
        window.minSize = fixedSize
        window.maxSize = fixedSize // Không cho phép resize cửa sổ welcome

        window.center()

        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true

        let controller = WelcomeWindowController(window: window)
        window.delegate = controller
        shared = controller

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        WelcomeWindowController.shared = nil
        NSApp.terminate(nil)
    }
}
