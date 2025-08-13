//
//  SettingsWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 10/08/2025.
//


class SettingsWindowController: NSWindowController {
    convenience init() {
        let settingsView = SettingsView() // SwiftUI view
        let hosting = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Cài đặt"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 500, height: 400))
        self.init(window: window)
    }
}
