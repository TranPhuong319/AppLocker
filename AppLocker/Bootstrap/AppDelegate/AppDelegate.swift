//
//  AppDelegate.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//

import AppKit
import Darwin
import Foundation
import LocalAuthentication
import Security
import ServiceManagement
import Sparkle
import SwiftUI
import UserNotifications

enum AgentAction {
    case install
    case uninstall
    case check
}

enum AppMode: String {
    case es = "ES"
    case launcher = "Launcher"
}

var modeLock: AppMode? = {
    if let savedValue = UserDefaults.standard.string(forKey: "selectedMode") {
        return AppMode(rawValue: savedValue)
    }
    return nil
}()

let plistName = "com.TranPhuong319.AppLocker.agent"
let loginItem = "com.TranPhuong319.AppLocker.LoginItems"

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    let helperIdentifier = "com.TranPhuong319.AppLocker.Helper"
    var pendingUpdate: SUAppcastItem?
    let notificationIndentifiers = "AppLockerUpdateNotification"
    var hotkey: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build-in Relaunch Wait: Check for -waitForPID argument
        let args = CommandLine.arguments
        Logfile.core.info("Launch Arguments: \(args)")

        if let index = args.firstIndex(of: "-waitForPID"),
            index + 1 < args.count,
            let pidString = args[index + 1] as String?,
            let parentProcessID = Int32(pidString) {

            Logfile.core.info("Waiting for PID: \(parentProcessID) to exit...")

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
                Logfile.core.info("Parent process exited.")
            }

            applicationExactlyOneInstance(ignoringPID: parentProcessID)
        } else {
            applicationExactlyOneInstance()
        }

        Logfile.core.info("AppLocker v\(Bundle.main.fullVersion) starting...")

        // Sử dụng optional chaining hoặc miêu tả enum an toàn
        Logfile.core.debug("Mode selected: \(modeLock?.rawValue ?? "None")")

        if let mode = modeLock {
            launchConfig(config: mode)
        } else {
            Logfile.core.info("Checking kext signing status...")
            if isKextSigningDisabled() {
                WelcomeWindowController.show()
                return
            } else {
                launchConfig(config: .launcher)
            }
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

        if !otherApps.isEmpty && !launchedByLaunchd() {
            Logfile.core.info(
                "Another instance is running (PIDs: \(otherApps.map { $0.processIdentifier })). Terminating."
            )
            NSApp.terminate(nil)
        }
    }
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var appBuild: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var fullVersion: String {
        "\(appVersion) (\(appBuild))"
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
