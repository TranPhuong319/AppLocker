//
//  AppDelegate.swift
//  AppLocker
//
//  Created by Doe Phương on 24/7/25.
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
    case esMode = "ES"
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

        // Sử dụng optional chaining hoặc miêu tả enum an toàn
        Logfile.core.debug("Mode selected: \(modeLock?.rawValue ?? "None", privacy: .public)")

        if let mode = modeLock {
            #if !DEBUG
            if mode == .esMode && !launchedByLaunchd() {
                let agent = SMAppService.agent(plistName: "\(plistName).plist")
                if agent.status == .enabled {
                    Logfile.core.log("App launched manually in esMode. Restarting via launchctl...")
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                    process.arguments = ["start", plistName]
                    try? process.run()
                    NSApp.terminate(nil)
                    return
                }
            }
            #endif
            
            launchConfig(config: mode)
        } else {
            WelcomeWindowController.show()
            return
        }
    }

    private func moveToApplicationsAndRelaunch() {
        let bundleURL = Bundle.main.bundleURL
        
        // Cố gắng tìm thư mục Applications phù hợp nhất (User trước, System sau)
        var targetApplicationsURL: URL?
        
        let userApplicationsURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        let systemApplicationsURL = URL(fileURLWithPath: "/Applications")
        
        // Nếu thư mục User/Applications tồn tại, ưu tiên dùng nó (không cần xin quyền root)
        if FileManager.default.fileExists(atPath: userApplicationsURL.path) {
            targetApplicationsURL = userApplicationsURL
        } else if FileManager.default.isWritableFile(atPath: systemApplicationsURL.path) {
            // Còn nếu System/Applications cho phép ghi, thì dùng system
            targetApplicationsURL = systemApplicationsURL
        } else {
            // Nếu cả 2 đều không có/không ghi được, tạo User/Applications
            do {
                try FileManager.default.createDirectory(at: userApplicationsURL, withIntermediateDirectories: true)
                targetApplicationsURL = userApplicationsURL
            } catch {
                Logfile.core.warning("Không thể tạo ~/Applications, fallback về /Applications")
                targetApplicationsURL = systemApplicationsURL
            }
        }
        
        guard let finalTargetURL = targetApplicationsURL else { return }
        let destinationURL = finalTargetURL.appendingPathComponent(bundleURL.lastPathComponent)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: bundleURL, to: destinationURL)
            
            do {
                try FileManager.default.trashItem(at: bundleURL, resultingItemURL: nil)
            } catch {
                Logfile.core.warning("Lỗi xóa file gốc: \(error.localizedDescription)")
            }
            
            Logfile.core.log("Đã di chuyển ứng dụng vào \(finalTargetURL.path). Đang khởi động lại...")
            
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            let pid = ProcessInfo.processInfo.processIdentifier
            configuration.arguments = ["-waitForPID", "\(pid)"]
            
            NSWorkspace.shared.openApplication(at: destinationURL, configuration: configuration) { app, error in
                if let error = error {
                    Logfile.core.error("Lỗi khởi động thư mục mới: \(error.localizedDescription)")
                }
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        } catch {
            Logfile.core.error("Lỗi khi di chuyển vào Applications: \(error.localizedDescription)")
            let errorAlert = NSAlert()
            errorAlert.alertStyle = .critical
            errorAlert.messageText = "Lỗi di chuyển ứng dụng"
            errorAlert.informativeText = "Không thể tự động di chuyển do thiếu quyền truy cập.\n\nVui lòng kéo thả thủ công ứng dụng vào thư mục Applications. Chi tiết lỗi: \(error.localizedDescription)"
            errorAlert.runModal()
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
            #if !DEBUG
            Logfile.core.warning(
                """
                Another instance is running \
                (PIDs: \(otherApps.map { $0.processIdentifier }, privacy: .public)). \
                Terminating.
                """
            )
            NSApp.terminate(nil)
            #else
            Logfile.core.warning(
                """
                Another instance is running \
                (PIDs: \(otherApps.map { $0.processIdentifier }, privacy: .public)). \
                Ignoring termination because of DEBUG mode.
                """
            )
            #endif
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
