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

    func application(_ application: NSApplication, open urls: [URL]) {
        Logfile.launcher.info("📂 AppDelegate got files: \(urls.map { $0.path }, privacy: .public)")

        guard let resourcesURL = Bundle.main.resourceURL else { return }
        let lockedApps = Launcher.shared.loadLockedAppInfos()

        if let appURL = try? FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" && $0.lastPathComponent.hasPrefix(".locked_") }) {

            let appName = appURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: ".locked_", with: "")
            let disguisedAppPath = "/Applications/\(appName).app"

            if lockedApps[disguisedAppPath] != nil {
                let realAppURL = URL(fileURLWithPath:"/Applications/.\(appName).app")

                // Check app thật đang chạy chưa
                let bundleID = Bundle(url: realAppURL)?.bundleIdentifier
                let isRunning = bundleID.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false

                let config = NSWorkspace.OpenConfiguration()

                if isRunning {
                    Logfile.launcher.info("🔁 Forwarding files to running app: \(urls.map(\.path))")
                    NSWorkspace.shared.open(urls, withApplicationAt: realAppURL, configuration: config) { _, err in
                        if let err = err {
                            Logfile.launcher.error("❌ Can't forward files: \(err.localizedDescription)")
                        } else {
                            Logfile.launcher.info("✅ Files forwarded successfully")
                        }
                    }
                } else {
                    Logfile.launcher.warning("⚠️ App not running, fallback to normal launch")
                    Launcher.shared.pendingOpenFileURLs.append(contentsOf: urls)
                    // để run() xử lý mở app lại
                }
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
