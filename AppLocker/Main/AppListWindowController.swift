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
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ContentView()
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480), // set 420x480
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )

        window.minSize = NSSize(width: 420, height: 480) // cố định min size
        window.maxSize = NSSize(width: 420, height: 480) // cố định max size (nếu muốn khóa resize)


        window.title = "Application_list_management".localized
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = nil // tạm thời nil

        let controller = AppListWindowController(window: window)
        window.delegate = controller
        shared = controller

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Xoá tham chiếu khi đóng
        AppListWindowController.shared = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        // Tự đóng nếu mất focus hoàn toàn
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let stillHasKeyWindow = NSApp.windows.contains(where: { $0.isKeyWindow })
            if !stillHasKeyWindow {
                self.close()
            }
        }
    }
}
