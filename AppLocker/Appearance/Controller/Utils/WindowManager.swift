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
    var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    var backingType: NSWindow.BackingStoreType = .buffered
    var isReleasedWhenClosed: Bool = false
    var level: NSWindow.Level = .normal
    var titleVisibility: NSWindow.TitleVisibility = .hidden
    var titlebarAppearsTransparent: Bool = true
    var wantsLayer: Bool = false
    var center: Bool = true
    var isOpaque: Bool = false
    var backgroundColor: NSColor? = .clear
    var autosaveName: NSWindow.FrameAutosaveName?
    var appearance: NSAppearance?
}

@MainActor
class WindowManager {
    static func createWindow(
        contentViewController: NSViewController,
        configuration: WindowConfiguration
    ) -> NSWindow {
        let window = NSWindow(contentViewController: contentViewController)

        let targetAppearance = configuration.appearance ?? NSApp.appDelegate?.currentThemeAppearance
            ?? AppDelegate.appearance(for: UserDefaults.standard.string(forKey: "appTheme") ?? "System")
        window.appearance = targetAppearance

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

        if let autosaveName = configuration.autosaveName {
            if !window.setFrameAutosaveName(autosaveName) && configuration.center {
                window.center()
            }
        } else if configuration.center {
            window.center()
        }

        return window
    }
}
