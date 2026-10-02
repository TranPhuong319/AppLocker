//
//  SettingsWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 26/8/25.
//

import SwiftUI
import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private let navigator = SettingsNavigator()

    private init() {
        let hostingController = NSHostingController(rootView: SettingsView(navigator: navigator))
        hostingController.sceneBridgingOptions = [.toolbars, .title]
        hostingController.sizingOptions = [.minSize, .maxSize]
        let initialSize = navigator.selectedTab.preferredSize
        hostingController.view.setFrameSize(initialSize)

        var config = WindowConfiguration()
        config.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        config.size = initialSize
        config.minSize = WindowLayout.settingsMinSize
        config.maxSize = nil
        config.autosaveName = "SettingsWindow"

        let window = WindowManager.createWindow(contentViewController: hostingController, configuration: config)
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        window.toolbar = toolbar

        super.init(window: window)
        window.delegate = self

        navigator.onTabChanged = { [weak self] newTab, oldTab in
            guard newTab == .logs || oldTab == .logs else { return }
            self?.resizeWindow(for: newTab)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func show(tab: SettingsTab? = nil) {
        if let tab {
            let oldTab = shared.navigator.selectedTab
            shared.navigator.selectedTab = tab
            if (tab == .logs || oldTab == .logs) && tab != oldTab {
                shared.resizeWindow(for: tab, animate: false)
            }
        }
        guard let window = shared.window else { return }
        shared.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func resizeWindow(for tab: SettingsTab, animate: Bool = true) {
        guard let window else { return }

        let targetContentSize = tab.preferredSize
        let extra = extraFrameInsets(for: window)
        let targetFrameWidth = targetContentSize.width + extra.width
        let targetFrameHeight = targetContentSize.height + extra.height
        let targetFrameSize = NSSize(width: targetFrameWidth, height: targetFrameHeight)

        let currentFrame = window.frame
        let widthChanged = abs(currentFrame.width - targetFrameSize.width) > 1
        let heightChanged = abs(currentFrame.height - targetFrameSize.height) > 1
        guard widthChanged || heightChanged else {
            return
        }

        let currentTop = currentFrame.origin.y + currentFrame.size.height
        let newOriginY = currentTop - targetFrameSize.height
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: newOriginY,
            width: targetFrameSize.width,
            height: targetFrameSize.height
        )

        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let finalFrame = constrained(frame: newFrame, targetSize: targetFrameSize, within: screenFrame)

        if animate && window.isVisible {
            window.setFrame(finalFrame, display: true, animate: true)
        } else {
            window.setFrame(finalFrame, display: true)
        }
    }

    private func extraFrameInsets(for window: NSWindow) -> (width: CGFloat, height: CGFloat) {
        if window.contentLayoutRect.width > 0 && window.contentLayoutRect.height > 0 {
            let extraW = max(0, window.frame.width - window.contentLayoutRect.width)
            let extraH = max(0, window.frame.height - window.contentLayoutRect.height)
            return (extraW, extraH)
        }
        let insets = window.contentView?.safeAreaInsets ?? NSEdgeInsets()
        return (insets.left + insets.right, insets.top + insets.bottom)
    }

    private func constrained(frame: NSRect, targetSize: NSSize, within screenFrame: NSRect?) -> NSRect {
        guard let screenFrame else { return frame }
        var adjusted = frame
        if adjusted.minY < screenFrame.minY {
            adjusted.origin.y = screenFrame.minY
        }
        if adjusted.maxY > screenFrame.maxY {
            adjusted.origin.y = screenFrame.maxY - targetSize.height
        }
        if adjusted.maxX > screenFrame.maxX {
            adjusted.origin.x = screenFrame.maxX - targetSize.width
        }
        if adjusted.minX < screenFrame.minX {
            adjusted.origin.x = screenFrame.minX
        }
        return adjusted
    }
}
