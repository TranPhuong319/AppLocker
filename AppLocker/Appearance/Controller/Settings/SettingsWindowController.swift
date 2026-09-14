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

    private let navigator = SettingsNavigator()

    private init() {
        let hostingController = NSHostingController(rootView: SettingsView(navigator: navigator))
        hostingController.sceneBridgingOptions = [.toolbars, .title]
        hostingController.sizingOptions = [.minSize, .maxSize, .intrinsicContentSize]
        hostingController.view.setFrameSize(WindowLayout.settingsSize)

        var config = WindowConfiguration()
        config.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        config.size = WindowLayout.settingsSize
        config.minSize = WindowLayout.settingsSize
        config.autosaveName = "SettingsWindow"

        let window = WindowManager.createWindow(contentViewController: hostingController, configuration: config)
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        window.toolbar = toolbar

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func show(tab: SettingsTab? = nil) {
        if let tab {
            shared.navigator.selectedTab = tab
        }
        guard let window = shared.window else { return }
        shared.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
