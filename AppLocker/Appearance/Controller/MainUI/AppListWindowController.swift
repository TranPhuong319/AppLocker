//
//  AppListWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 24/7/25.
//

import AppKit
import SwiftUI

@MainActor
final class AppListWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AppListWindowController()

    private init() {
        let hostingController = Self.createHostingController()
        let window = Self.createMainAppWindow(with: hostingController)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func show() {
        guard let window = shared.window else { return }

        shared.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        if let hostingController = window.contentViewController {
            window.makeFirstResponder(hostingController)
        }
        NSApp.activate()
    }

    // MARK: - Helper Methods
    private static func createHostingController() -> NSHostingController<ContentView> {
        let hostingController = NSHostingController(rootView: ContentView())
        hostingController.sceneBridgingOptions = [.toolbars, .title]
        hostingController.view.setFrameSize(WindowLayout.mainSize)
        return hostingController
    }

    private static func createMainAppWindow(with contentVC: NSViewController) -> NSWindow {
        let size = WindowLayout.mainSize
        var config = WindowConfiguration()
        config.title = String(localized: "Locked application")
        config.styleMask = [.titled, .closable, .fullSizeContentView]
        config.titleVisibility = .visible
        config.titlebarAppearsTransparent = true
        config.level = .floating
        config.size = size
        config.minSize = size
        config.maxSize = size
        config.isOpaque = false
        config.backgroundColor = .clear

        return WindowManager.createWindow(contentViewController: contentVC, configuration: config)
    }

    // MARK: - NSWindowDelegate
    func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor [weak self] in
            // Delay 0,1 second
            try? await Task.sleep(for: .milliseconds(100))
            guard let self else { return }

            let stillHasKeyWindow = NSApp.windows.contains(where: { $0.isKeyWindow })
            if !stillHasKeyWindow {
                self.close()
            }
        }
    }
}
