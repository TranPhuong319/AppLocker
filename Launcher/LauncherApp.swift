//
//  LauncherApp.swift
//  Launcher
//
//  Created by Doe Phương on 29/07/2025.
//

import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)

        // Gọi hàm run của Launcher ở đây
        Launcher.shared.run()
    }
}

@main
struct LauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {} // Không cần UI
    }
}
