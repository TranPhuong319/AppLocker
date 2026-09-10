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
        hostingController.sceneBridgingOptions = [.title]
        hostingController.sizingOptions = [.minSize, .maxSize, .intrinsicContentSize]

        var config = WindowConfiguration()
        config.styleMask = [.titled, .closable, .fullSizeContentView]
        config.size = WindowLayout.aboutSize
        config.minSize = WindowLayout.aboutSize
        config.maxSize = WindowLayout.aboutSize
        config.isReleasedWhenClosed = false
        config.center = true

        let window = WindowManager.createWindow(contentViewController: hostingController, configuration: config)
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func show() {
        guard let window = shared.window else { return }
        window.setContentSize(WindowLayout.aboutSize)
        window.center()
        shared.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
