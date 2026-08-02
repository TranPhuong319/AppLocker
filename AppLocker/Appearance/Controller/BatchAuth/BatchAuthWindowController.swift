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
        let size = WindowLayout.BatchAuth.size
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        super.init(window: window)
        window.delegate = self
        setupContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContentView() {
        guard let window = window else { return }
        let contentView = BatchAuthView(
            server: XPCServer.shared,
            onAuthenticate: {
                XPCServer.shared.handleAuthenticate()
            },
            onCancel: {
                XPCServer.shared.handleCancel()
            }
        )
        window.contentView = NSHostingView(rootView: contentView)
    }

    func showWindow() {
        guard let window = window else { return }

        if !window.isVisible {
            window.center()
        }

        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
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
