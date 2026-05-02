//
//  AboutWindowController.swift
//  AppLocker
//
//  Created by AppLocker
//

import Cocoa
import SwiftUI

class AboutWindowController: NSWindowController {

    static var shared: AboutWindowController?

    static func show() {
        if shared == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.center()
            window.isReleasedWhenClosed = false
            
            let hostingView = NSHostingView(rootView: AboutView())
            window.contentView = hostingView
            
            shared = AboutWindowController(window: window)
        }
        
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
