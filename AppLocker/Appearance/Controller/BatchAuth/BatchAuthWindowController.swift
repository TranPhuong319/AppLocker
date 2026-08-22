//
//  BatchAuthWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 31/7/26.
//

import AppKit
import Foundation
import SwiftUI
import os

@MainActor
final class BatchAuthWindowController: NSWindowController, NSWindowDelegate {
    static let shared = BatchAuthWindowController()

    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }

    private init() {
        let contentView = BatchAuthView(
            server: XPCServer.shared,
            onAuthenticate: {
                XPCServer.shared.handleAuthenticate()
            },
            onCancel: {
                XPCServer.shared.handleCancel()
            }
        )
        let hostingController = NSHostingController(rootView: contentView)
        if #available(macOS 14.0, *) {
            hostingController.sceneBridgingOptions = [.toolbars, .title]
        }
        hostingController.view.setFrameSize(WindowLayout.batchAuthSize)

        let size = WindowLayout.batchAuthSize
        var config = WindowConfiguration()
        config.title = String(localized: "Authentication")
        config.styleMask = [.titled, .closable, .fullSizeContentView]
        config.titleVisibility = .visible
        config.titlebarAppearsTransparent = true
        config.isOpaque = false
        config.backgroundColor = .clear
        config.isReleasedWhenClosed = false
        config.level = .floating
        config.size = size
        config.minSize = size
        config.maxSize = size
        config.center = true

        let window = WindowManager.createWindow(contentViewController: hostingController, configuration: config)
        let toolbar = NSToolbar(identifier: "BatchAuthToolbar")
        window.toolbar = toolbar
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        guard let window = window else { return }

        if !window.isVisible {
            window.center()
        }

        NSRunningApplication.current.activate()
        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    func hideWindow() {
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        XPCServer.shared.handleCancel()
        return true
    }
}
