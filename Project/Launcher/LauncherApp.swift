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
        Launcher.shared.run()
    }

    // ✅ Nhận file khi người dùng "Open With..." hoặc double click
    func application(_ application: NSApplication, open urls: [URL]) {
        print("📂 AppDelegate got files:", urls.map { $0.path })
        Launcher.shared.pendingOpenFileURLs.append(contentsOf: urls)
    }
}

@main
struct LauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {} // Không cần UI
    }
}
