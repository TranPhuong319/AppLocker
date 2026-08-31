//
//  AboutWindowController.swift
//  AppLocker
//
//  Created by AppLocker
//

import Cocoa
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
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
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func show() {
        shared.window?.center()
        shared.showWindow(nil)
        shared.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
