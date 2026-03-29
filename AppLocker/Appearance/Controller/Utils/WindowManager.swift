//
//  WindowManager.swift
//  AppLocker
//

import AppKit
import SwiftUI

struct WindowConfiguration {
    var title: String = ""
    var size: NSSize? = nil
    var minSize: NSSize? = nil
    var maxSize: NSSize? = nil
    var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
    var backingType: NSWindow.BackingStoreType = .buffered
    var isReleasedWhenClosed: Bool = false
    var level: NSWindow.Level = .normal
    var titleVisibility: NSWindow.TitleVisibility = .visible
    var titlebarAppearsTransparent: Bool = false
    var wantsLayer: Bool = false
    var center: Bool = true
}

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
