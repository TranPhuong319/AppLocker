//
//  WindowManager.swift
//  AppLocker
//
//  Created by Doe Phương on 29/3/26.
//

import AppKit
import SwiftUI

struct WindowConfiguration {
    var title: String = ""
    var size: NSSize?
    var minSize: NSSize?
    var maxSize: NSSize?
    var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
    var backingType: NSWindow.BackingStoreType = .buffered
    var isReleasedWhenClosed: Bool = false
    var level: NSWindow.Level = .normal
    var titleVisibility: NSWindow.TitleVisibility = .visible
    var titlebarAppearsTransparent: Bool = false
    var wantsLayer: Bool = false
    var center: Bool = true
    var isOpaque: Bool = true
    var backgroundColor: NSColor? = .windowBackgroundColor
}

@MainActor
class WindowManager {
    static func createWindow(
        contentViewController: NSViewController,
        configuration: WindowConfiguration
    ) -> NSWindow {
        let window = NSWindow(contentViewController: contentViewController)

        window.styleMask = configuration.styleMask
        window.backingType = configuration.backingType
        window.title = configuration.title
        window.isReleasedWhenClosed = configuration.isReleasedWhenClosed
        window.level = configuration.level
        window.titleVisibility = configuration.titleVisibility
        window.titlebarAppearsTransparent = configuration.titlebarAppearsTransparent
        window.isOpaque = configuration.isOpaque
        window.isMovableByWindowBackground = false

        if let backgroundColor = configuration.backgroundColor {
            window.backgroundColor = backgroundColor
        }

        if configuration.wantsLayer {
            window.contentView?.wantsLayer = true
        }

        if let size = configuration.size {
            window.setContentSize(size)
        }
        if let minSize = configuration.minSize {
            window.minSize = minSize
        }
        if let maxSize = configuration.maxSize {
            window.maxSize = maxSize
        }

        if configuration.center {
            window.center()
        }

        return window
    }
}
