//
//  AppListWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 24/7/25.
//

import AppKit
import SwiftUI

class TouchBarHostingController<Content: View>: NSHostingController<Content> {
    override func makeTouchBar() -> NSTouchBar? {
        return TouchBarManager.shared.makeTouchBar(for: AppState.shared.activeTouchBar)
    }
}

class AppListWindowController: NSWindowController, NSWindowDelegate {
    static var shared: AppListWindowController?

    static func show() {
        NSApp.activate(ignoringOtherApps: true)

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
        NSApp.activate(ignoringOtherApps: true)
    }


    private static func createHostingController() -> TouchBarHostingController<ContentView> {
        let hostingController = TouchBarHostingController(rootView: ContentView())

        hostingController.view.setFrameSize(WindowLayout.Main.size)
        hostingController.view.layoutSubtreeIfNeeded()
        return hostingController
    }

    private static func createMainAppWindow(with contentVC: NSViewController) -> NSWindow {
        let size = WindowLayout.Main.size
        var config = WindowConfiguration()
        config.title = String(localized: "Manage the application list")
        config.styleMask = [.titled, .closable, .fullSizeContentView]
        config.level = .floating
        config.size = size
        config.minSize = size
        config.maxSize = size
        
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
