//
//  AppDelegate.swift
//  AppLocker
//
//  Created by Doe Phương on 24/7/25.
//

import AppKit
import Foundation
import ServiceManagement
import Sparkle
import SwiftUI
import UserNotifications

enum AgentAction {
    case install
    case uninstall
    case check
}

let plistName = "com.TranPhuong319.AppLocker.agent"

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var pendingUpdate: SUAppcastItem?
    let notificationIndentifiers = "AppLockerUpdateNotification"
    var hotkey: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build-in Relaunch Wait: Check for -waitForPID argument
        let args = CommandLine.arguments
        Logfile.core.debug("Launch Arguments: \(args)")

        if let index = args.firstIndex(of: "-waitForPID"),
            index + 1 < args.count,
            let pidString = args[index + 1] as String?,
            let parentProcessID = Int32(pidString) {

            Logfile.core.log("Waiting for PID: \(parentProcessID, privacy: .public) to exit...")

            // Wait for parent process to exit
            // kill(pid, 0) returns 0 if process exists/is reachable
            var attempts = 0
            while kill(parentProcessID, 0) == 0 && attempts < 30 {  // Check for 3s (30 * 0.1s)
                usleep(100000)  // 0.1s
                attempts += 1
            }
            if attempts >= 30 {
                Logfile.core.warning("Wait timed out after 3 seconds. Proceeding anyway.")
            } else {
                Logfile.core.log("Parent process exited.")
            }

            applicationExactlyOneInstance(ignoringPID: parentProcessID)
        } else {
            applicationExactlyOneInstance()
        }

        #if !DEBUG
        checkAndMoveToApplications()
        #endif

        Logfile.core.log("AppLocker v\(Bundle.main.fullVersion, privacy: .public) starting...")

        #if !DEBUG
        if !launchedByLaunchd() {
            let agent = SMAppService.agent(plistName: "\(plistName).plist")
            if agent.status == .enabled {
                Logfile.core.log("App launched manually. Restarting via launchctl...")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = ["start", plistName]
                try? process.run()
                NSApp.terminate(nil)
                return
            }
        }
        #endif

        let isFirstStart = UserDefaults.standard.object(forKey: "isFirstStart") as? Bool ?? true

        if isFirstStart {
            Logfile.core.log("First launch. Showing welcome/ToS screen.")
            WelcomeWindowController.show()
        } else {
            Logfile.core.log("Not first launch. Running normal launch configuration.")
            launchConfig()
        }
    }

    func applicationExactlyOneInstance(ignoringPID: Int32? = nil) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)

        // Filter out the current process and the ignored PID
        let otherApps = apps.filter { app in
            return app.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && app.processIdentifier != ignoringPID
        }

        if !otherApps.isEmpty {
            Logfile.core.warning(
                """
                Another instance is running \
                (PIDs: \(otherApps.map { $0.processIdentifier }, privacy: .public)). \
                Activating existing instance and terminating this new instance.
                """
            )
            otherApps.first?.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
        }
    }
}

extension SMAppService.Status {
    public var description: String {
        switch self {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        default: return "unknown(\(rawValue))"
        }
    }
}

extension NSApplication {
    var appDelegate: AppDelegate? {
        delegate as? AppDelegate
    }
}
