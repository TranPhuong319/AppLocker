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
    var isCompletingOnboarding = false

    static func show() {
        if let controller = shared {
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let contentView = WelcomeView()
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.sceneBridgingOptions = [.toolbars, .title]

        let fixedSize = WindowLayout.welcomeSize
        hostingController.view.setFrameSize(fixedSize)

        let bundle = Bundle.main

        var config = WindowConfiguration()
        config.title = String(localized: "Welcome to \(bundle.appName)")
        config.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        config.titleVisibility = .hidden
        config.titlebarAppearsTransparent = true
        config.wantsLayer = true
        config.isOpaque = false
        config.backgroundColor = .clear
        config.size = fixedSize
        config.minSize = fixedSize
        config.maxSize = fixedSize
        config.center = true

        let window = WindowManager.createWindow(contentViewController: hostingController, configuration: config)
        let toolbar = NSToolbar(identifier: "WelcomeToolbar")
        window.toolbar = toolbar
        window.isMovableByWindowBackground = false

        let controller = WelcomeWindowController(window: window)
        window.delegate = controller
        shared = controller

        NSApp.activate()
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        WelcomeWindowController.shared = nil
        if !isCompletingOnboarding {
            NSApp.terminate(nil)
        }
    }
}
