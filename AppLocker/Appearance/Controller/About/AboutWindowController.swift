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
            var config = WindowConfiguration()
            config.styleMask = [.titled, .closable, .fullSizeContentView]
            config.titlebarAppearsTransparent = true
            config.titleVisibility = .hidden
            config.size = WindowLayout.About.size
            config.isReleasedWhenClosed = false
            config.center = true

            let window = WindowManager.createWindow(contentViewController: hostingController, configuration: config)
            window.isMovableByWindowBackground = true

            shared = AboutWindowController(window: window)
        }

        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
