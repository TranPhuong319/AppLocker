//
//  SettingsWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import AppKit
import SwiftUI

class SettingsWindowController {
    static var shared: NSWindow?

    static func show() {
        if let window = shared {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ContentView()
        let hosting = NSHostingView(rootView: contentView)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false
        )

        window.title = "AppLocker Settings"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()

        shared = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
