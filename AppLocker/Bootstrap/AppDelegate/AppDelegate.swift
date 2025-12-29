//
//  AppDelegate.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//

import AppKit
import LocalAuthentication
import Security
import ServiceManagement
import Foundation
import SwiftUI
import UserNotifications
import Sparkle

enum AgentAction {
    case install
    case uninstall
    case checkAndInstallifNeed
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

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = AppDelegate()
    var statusItem: NSStatusItem?
    let helperIdentifier = "com.TranPhuong319.AppLocker.Helper"
    var pendingUpdate: SUAppcastItem?
    let notificationIndentifiers = "AppLockerUpdateNotification"
    var hotkey: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logfile.core.info("AppLocker v\(Bundle.main.fullVersion) starting...")

        // Sử dụng optional chaining hoặc miêu tả enum an toàn
        Logfile.core.debug("Mode selected: \(modeLock?.rawValue ?? "None")")

        Logfile.core.info("Checking kext signing status...")

        if isKextSigningDisabled() {
            if let mode = modeLock {
                launchConfig(config: mode)
            } else {
                WelcomeWindowController.show()
                return
            }
        } else {
            launchConfig(config: .launcher)
        }
    }

    func applicationExactlyOneInstance() {
        // EN: macOS typically enforces single instance via NSApplication.
        // VI: macOS thường đảm bảo một instance qua NSApplication.
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        if apps.count > 1 {
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
