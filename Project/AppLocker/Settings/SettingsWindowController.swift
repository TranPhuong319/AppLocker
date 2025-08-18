//
//  SettingsWindowController.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//


import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    convenience init() {
        let settingsView = SettingsView()
        let hosting = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hosting)
        
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.title = "Cài đặt"
        
        // Chỉ cho đóng, không cho thu nhỏ / resize
        window.styleMask = [
            .titled,
            .closable
        ]
        
        let fixedHeight: CGFloat = 200
        window.setContentSize(NSSize(width: 600, height: fixedHeight))
        window.minSize = NSSize(width: 400, height: fixedHeight)
        window.maxSize = NSSize(width: 1200, height: fixedHeight)

        
        // Luôn mở giữa màn hình
        window.center()
        
        self.init(window: window)
    }
}
