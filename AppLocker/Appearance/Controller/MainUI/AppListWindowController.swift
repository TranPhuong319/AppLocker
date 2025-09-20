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
    
    // Hiển thị cửa sổ quản lý danh sách ứng dụng
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
            keyWin.makeKeyAndOrderFront(nil)
            invisibleKeyWindow = keyWin
        }
        
        // Tạo floating window
        let contentView = ContentView()
        let hostingController = TouchBarHostingController(rootView: contentView)
        hostingController.touchBarType = .mainWindow

        // Ép SwiftUI layout trước khi attach window
        hostingController.view.setFrameSize(NSSize(width: CGFloat(AppState.shared.setWidth), height: CGFloat(AppState.shared.setHeight)))
        hostingController.view.layoutSubtreeIfNeeded()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: CGFloat(AppState.shared.setWidth), height: CGFloat(AppState.shared.setHeight)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        [.miniaturizeButton, .zoomButton].forEach {
            window.standardWindowButton($0)?.isHidden = true
        }
        window.contentViewController = hostingController
        let fixedSize = NSSize(width: CGFloat(AppState.shared.setWidth),
                               height: CGFloat(AppState.shared.setHeight))
        window.setContentSize(fixedSize)
        window.minSize = fixedSize
        window.maxSize = fixedSize
        window.title = "Manage the application list".localized
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        
        // Show window
        let controller = AppListWindowController(window: window)
        window.delegate = controller
        shared = controller
        
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hostingController)
        NSApp.activate(ignoringOtherApps: true)
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

