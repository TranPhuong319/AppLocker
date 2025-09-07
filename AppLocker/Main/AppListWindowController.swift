//
//  AppListWindowController.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//

import AppKit
import SwiftUI

class TouchBarHostingController<Content: View>: NSHostingController<Content> {
    override func makeTouchBar() -> NSTouchBar? {
        return TouchBarManager.shared.makeTouchBar()
    }
}

class AppListWindowController: NSWindowController, NSWindowDelegate {
    static var shared: AppListWindowController?
    private static var invisibleKeyWindow: NSWindow?
    
    static func show() {
        if let controller = shared {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Tạo invisible key window hack Touch Bar
        if invisibleKeyWindow == nil {
            let keyWin = NSWindow(
                contentRect: .zero,
                styleMask: [],
                backing: .buffered,
                defer: false
            )
            keyWin.alphaValue = 0
            keyWin.isOpaque = false
            keyWin.level = .normal
            keyWin.makeKeyAndOrderFront(nil)
            invisibleKeyWindow = keyWin
        }
        
        // Tạo floating window
        let contentView = ContentView()
        let hostingController = TouchBarHostingController(rootView: contentView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: 450, height: 350))
        window.minSize = NSSize(width: 450, height: 350)
        window.maxSize = NSSize(width: 450, height: 350)
        window.title = "Manage the application list".localized
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        
        // Show window
        let controller = AppListWindowController(window: window)
        window.delegate = controller
        shared = controller
        
        controller.showWindow(nil)
        controller.updateTouchBar(for: .mainWindow)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hostingController)
        NSApp.activate(ignoringOtherApps: true)
    }
    
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

extension AppListWindowController {

    func updateTouchBar(for type: AppState.TouchBarType) {
        guard let window = self.window else { return }

        // 1️⃣ Tạo NSTouchBar mới
        let touchBar = NSTouchBar()
        touchBar.defaultItemIdentifiers = []

        switch type {
        case .mainWindow:
            TouchBarManager.shared.registerOrUpdateItem(id: .addApp) {
                let symbolImage = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add App")
                let button = NSButton(image: symbolImage!, target: TouchBarActionProxy.shared, action: #selector(TouchBarActionProxy.shared.openPopupAddApp))
                button.isBordered = true
                return button
            }
        case .addAppPopup:
            TouchBarManager.shared.registerOrUpdateItem(id: .lockButton) {
                let symbolImage = NSImage(systemSymbolName: "lock", accessibilityDescription: "Add App")
                let button = NSButton(image: symbolImage!, target: TouchBarActionProxy.shared, action: #selector(TouchBarActionProxy.shared.lockApp))
                button.isBordered = true
                return button
            }
        case .deleteQueuePopup:
            TouchBarManager.shared.registerOrUpdateItem(id: .unlockButton) {
                let symbolImage = NSImage(systemSymbolName: "lock.open", accessibilityDescription: "Add App")
                let button = NSButton(image: symbolImage!, target: TouchBarActionProxy.shared, action: #selector(TouchBarActionProxy.shared.unlockApp))
                button.isBordered = true
                return button
            }
        }

        TouchBarManager.shared.apply(to: window)
    }
}
