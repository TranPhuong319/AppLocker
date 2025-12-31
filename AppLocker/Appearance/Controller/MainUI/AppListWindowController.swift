//
//  AppListWindowController.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//

import AppKit
import SwiftUI

class TouchBarHostingController<Content: View>: NSHostingController<Content> {
    var touchBarType: AppState.TouchBarType?

    override func makeTouchBar() -> NSTouchBar? {
        guard let type = touchBarType else { return nil }
        return TouchBarManager.shared.makeTouchBar(for: type)
    }
}

class AppListWindowController: NSWindowController, NSWindowDelegate {
    static var shared: AppListWindowController?
    private static var invisibleKeyWindow: NSWindow?

    static func show() {
        if let controller = shared {
            activateExistingWindow(controller)
            return
        }

        ensureInvisibleKeyWindow()

        let hostingController = createHostingController()

        let window = createMainAppWindow(with: hostingController)

        let controller = AppListWindowController(window: window)
        window.delegate = controller
        shared = controller

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hostingController)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Helper Methods
    private static func activateExistingWindow(_ controller: NSWindowController) {
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func ensureInvisibleKeyWindow() {
        guard invisibleKeyWindow == nil else { return }
        let keyWin = NSWindow(
            contentRect: .zero,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        keyWin.alphaValue = 0
        keyWin.isOpaque = false
        keyWin.makeKeyAndOrderFront(nil)
        invisibleKeyWindow = keyWin
    }

    private static func createHostingController() -> TouchBarHostingController<ContentView> {
        let hostingController = TouchBarHostingController(rootView: ContentView())
        hostingController.touchBarType = .mainWindow

        let size = NSSize(width: AppState.shared.setWidth, height: AppState.shared.setHeight)
        hostingController.view.setFrameSize(size)
        hostingController.view.layoutSubtreeIfNeeded()
        return hostingController
    }

    private static func createMainAppWindow(with contentVC: NSViewController) -> NSWindow {
        let size = NSSize(width: AppState.shared.setWidth, height: AppState.shared.setHeight)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "Manage the application list".localized
        window.contentViewController = contentVC
        window.setContentSize(size)
        window.minSize = size
        window.maxSize = size
        window.isReleasedWhenClosed = false
        window.level = .floating
//
//        [.miniaturizeButton, .zoomButton].forEach {
//            window.standardWindowButton($0)?.isHidden = true
//        }

        return window
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
