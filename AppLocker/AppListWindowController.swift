//
//  SettingsWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import AppKit
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

        let contentView = ContentView()
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )

        window.title = "Quản lý danh sách Ứng dụng"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = nil // tạm thời nil

        let controller = SettingsWindowController(window: window)
        window.delegate = controller
        shared = controller

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Xoá tham chiếu khi đóng
        SettingsWindowController.shared = nil
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
