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
        // App launcher không có UI
        NSApp.setActivationPolicy(.prohibited)
        Launcher.shared.run()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let filePaths = urls.map { $0.path }
        Logfile.launcher.pInfo("AppDelegate got files: \(filePaths)")

        let lockedApps = Launcher.shared.loadLockedAppInfos()

        // Dò trong danh sách app đã lock
        for (launcherPath, _) in lockedApps {
            let disguisedAppURL = URL(fileURLWithPath: launcherPath)

            // Nếu launcher tồn tại thì lấy ra app thật
            if FileManager.default.fileExists(atPath: disguisedAppURL.path) {
                let appName = disguisedAppURL.deletingPathExtension().lastPathComponent // "Marked 2"
                let realAppURL = disguisedAppURL.deletingLastPathComponent()
                    .appendingPathComponent(".\(appName).app")

                // Check app thật có đang chạy chưa
                let bundleID = Bundle(url: realAppURL)?.bundleIdentifier
                let isRunning = bundleID.map {
                    !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
                } ?? false

                let config = NSWorkspace.OpenConfiguration()

                if isRunning {
                    Logfile.launcher.info("Forwarding files to running app: \(urls.map(\.path))")
                    NSWorkspace.shared.open(urls, withApplicationAt: realAppURL, configuration: config) { _, err in
                        if let err = err {
                            Logfile.launcher.error("Can't forward files: \(err.localizedDescription)")
                        } else {
                            Logfile.launcher.info("Files forwarded successfully")
                        }
                    }
                } else {
                    Logfile.launcher.warning("App not running, fallback to normal launch")
                    Launcher.shared.pendingOpenFileURLs.append(contentsOf: urls)
                }

                break // xử lý xong app match thì dừng
            }
        }
    }
}

@main
struct LauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {} // Không cần UI
    }
}
