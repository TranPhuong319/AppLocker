//
//  CustomApplication.swift
//  AppLocker
//
//  Created by Doe Phương on 6/11/25.
//

import AppKit

class CustomApplication: NSApplication {
    private var canQuitByUser: Bool {
        #if DEBUG
        return true
        #else
        return WelcomeWindowController.shared != nil
        #endif
    }

    override func sendEvent(_ event: NSEvent) {
        // Chặn phím tắt Command + Q ngoài màn hình Welcome (bản Release)
        if !canQuitByUser,
           event.type == .keyDown,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            return
        }

        super.sendEvent(event)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(NSApplication.terminate(_:)) {
            let allowed = canQuitByUser
            menuItem.isHidden = !allowed
            return allowed
        }
        return super.validateMenuItem(menuItem)
    }
}
