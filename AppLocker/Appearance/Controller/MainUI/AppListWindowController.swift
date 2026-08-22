//
//  AppListWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 24/7/25.
//

import AppKit
import SwiftUI

class AppListWindowController: NSWindowController, NSWindowDelegate {
    static var shared: AppListWindowController?

    static func show() {
        NSApp.activate()

        if let controller = shared {
            activateExistingWindow(controller)
            return
        }

        let hostingController = createHostingController()
        let window = createMainAppWindow(with: hostingController)

        let controller = AppListWindowController(window: window)
        window.delegate = controller
        shared = controller

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hostingController)
    }

    // MARK: - Helper Methods
    private static func activateExistingWindow(_ controller: NSWindowController) {
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private static func createHostingController() -> NSHostingController<ContentView> {
        let hostingController = NSHostingController(rootView: ContentView())
        if #available(macOS 14.0, *) {
            hostingController.sceneBridgingOptions = [.toolbars, .title]
        }
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
    func windowWillClose(_ notification: Notification) {
        AppListWindowController.shared = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let stillHasKeyWindow = NSApp.windows.contains(where: { $0.isKeyWindow })
            if !stillHasKeyWindow {
                self.close()
            }
        }
    }
}
