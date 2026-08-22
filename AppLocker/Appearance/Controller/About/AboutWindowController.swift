//
//  AboutWindowController.swift
//  AppLocker
//
//  Created by AppLocker
//

import Cocoa
import SwiftUI

class AboutWindowController: NSWindowController {

    static var shared: AboutWindowController?

    static func show() {
        if shared == nil {
            let hostingController = NSHostingController(rootView: AboutView())
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

            var config = WindowConfiguration()
            config.styleMask = [.titled, .closable, .fullSizeContentView]
            config.titlebarAppearsTransparent = true
            config.titleVisibility = .hidden
            config.isOpaque = true
            config.backgroundColor = .windowBackgroundColor
            config.size = WindowLayout.aboutSize
            config.isReleasedWhenClosed = false
            config.center = true

            let window = WindowManager.createWindow(contentViewController: hostingController, configuration: config)
            window.isMovableByWindowBackground = false

            shared = AboutWindowController(window: window)
        }

        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
