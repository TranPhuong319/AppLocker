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

    // Hiển thị cửa sổ settings
    static func show() {
        if let controller = shared {
            NSApp.activate(ignoringOtherApps: true)        // activate trước
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = WelcomeView()
        let hostingView = NSHostingView(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 450),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.center()

        window.contentView = hostingView
        window.title = "Welcome to AppLocker".localized
        [.miniaturizeButton, .zoomButton].forEach {
            window.standardWindowButton($0)?.isHidden = true
        }
        let controller = WelcomeWindowController(window: window)
        window.delegate = controller
        shared = controller
        
        // Bật app trước khi show
        NSApp.activate(ignoringOtherApps: true)

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}
