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

        let fixedSize = WindowLayout.Welcome.size
        
        var config = WindowConfiguration()
        config.title = String(localized: "Welcome to AppLocker")
        config.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        config.titleVisibility = .hidden
        config.titlebarAppearsTransparent = true
        config.wantsLayer = true
        config.size = fixedSize
        config.minSize = fixedSize
        config.maxSize = fixedSize
        
        let window = WindowManager.createWindow(contentViewController: hostingController, configuration: config)
//
//        window.standardWindowButton(.zoomButton)?.isHidden = true
//        window.standardWindowButton(.miniaturizeButton)?.isHidden = true

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
