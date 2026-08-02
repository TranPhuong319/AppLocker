//
//  CustomApplication.swift
//  AppLocker
//
//  Created by Doe Phương on 6/11/25.
//

import AppKit

class CustomApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        // Chặn phím tắt Command + Q
        if event.type == .keyDown,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            return
        }

        super.sendEvent(event)
    }

    // MARK: - Disable AppKit AppIntents & Shortcuts auto-registration
    @objc func _registerWithIntentsFramework() {}
    @objc func _registerAppIntents() {}
    @objc func _setupAppIntents() {}
    @objc func _setupAppIntentsIfNeeded() {}
    @objc func _registerAutoShortcuts() {}
    @objc func _registerWithShortcutsFramework() {}
}
