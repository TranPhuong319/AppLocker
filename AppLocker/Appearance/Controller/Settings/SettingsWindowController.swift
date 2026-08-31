//
//  SettingsWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 26/8/25.
//

import SwiftUI
import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        let hostingController = NSHostingController(rootView: SettingsView())
        if #available(macOS 14.0, *) {
            hostingController.sceneBridgingOptions = [.toolbars, .title]
        }

        var config = WindowConfiguration()
        config.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        config.titlebarAppearsTransparent = true
        config.titleVisibility = .hidden
        config.isOpaque = true
        config.backgroundColor = .windowBackgroundColor
        config.minSize = NSSize(width: 640, height: 440)

        let window = WindowManager.createWindow(contentViewController: hostingController, configuration: config)
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        window.toolbar = toolbar
        window.setContentSize(NSSize(width: 640, height: 440))
        window.minSize = NSSize(width: 640, height: 440)
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func show() {
        guard let window = shared.window else { return }
        window.center()
        shared.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        var size = frameSize
        if size.width < 640 { size.width = 640 }
        if size.height < 440 { size.height = 440 }
        return size
    }
}
