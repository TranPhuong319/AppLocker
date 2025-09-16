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

enum LoginAction {
    case none      // Only check status
    case install   // Install the helper tool
    case uninstall // Uninstall the helper tool
}

// MARK: AppDelegate.swift
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = AppDelegate()
    var statusItem: NSStatusItem?
    let helperIdentifier = "com.TranPhuong319.AppLockerHelper"
    var pendingUpdate: SUAppcastItem?
    let notificationIndentifiers = "AppLockerUpdateNotification"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logfile.core.debug("Loading Application")

        HelperInstaller.checkAndAlertBlocking(helperToolIdentifier: helperIdentifier)
        setupMenuBar()
        
        AppUpdater.shared.setBridgeDelegate(self)
        AppUpdater.shared.startTestAutoCheck()

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { granted, error in
            if let error = error { Logfile.core.error("Notification error: \(error, privacy: .public)") }
        }
//        NSApplication.autoCenterAllWindows()
    }
}

// MARK: - Menu Bar
extension AppDelegate: NSMenuDelegate {
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "AppLocker")

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if NSEvent.modifierFlags.contains(.option) {
            buildOptionMenu(for: menu)
        } else {
            buildNormalMenu(for: menu)
        }
    }

    private func buildNormalMenu(for menu: NSMenu) {
        menu.addItem(NSMenuItem(title: "Manage the application list".localized,
                                action: #selector(openListApp),
                                keyEquivalent: "s"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AppLocker".localized,
                                action: #selector(quitApp),
                                keyEquivalent: "q"))
    }

    private func buildOptionMenu(for menu: NSMenu) {
        menu.addItem(NSMenuItem(title: "Settings".localized,
                                action: #selector(openPreference),
                                keyEquivalent: ""))
        menu.addItem(.separator())

        let launchItem = NSMenuItem(title: "Launch At Login".localized,
                                    action: #selector(launchAtLogin),
                                    keyEquivalent: "")
        launchItem.target = self
        launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem(title: "Check for Updates...".localized,
                                action: #selector(checkUpdate),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About AppLocker".localized,
                                action: #selector(about),
                                keyEquivalent: ""))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Uninstall AppLocker".localized,
                                action: #selector(uninstall),
                                keyEquivalent: ""))
    }
}

// MARK: - App Actions
extension AppDelegate {
    @objc func openListApp() {
        AuthenticationManager.authenticate(
            reason: "authenticate to open the application list".localized
        ) { success, error in
            DispatchQueue.main.async {
                if success {
                    AppListWindowController.show()
                    Logfile.core.debug("Opened AppList")
                } else {
                    Logfile.core.error("Error opening list app: \(error as NSObject?, privacy: .public)")
                }
            }
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func openPreference() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.show()
    }

    @objc func uninstall() {
        Logfile.core.info("Uninstall Clicked")
        let manager = LockManager()
        
        NSApp.activate(ignoringOtherApps: true)

        if manager.lockedApps.isEmpty {
            let confirm = AlertShow.show(title: "Uninstall Applocker?".localized,
                                    message: "You are about to uninstall AppLocker. Please make sure that all apps are unlocked!%@Your Mac will restart after Successful Uninstall".localized(with: "\n\n"),
                                    style: .critical,
                                    buttons: ["Uninstall".localized, "Cancel".localized])
            
            switch confirm {
            case .button(index: 0, title: "Uninstall".localized):
                AuthenticationManager.authenticate(
                    reason: "uninstall the application".localized
                ) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            self.callUninstallHelper()
                            let loginItem = SMAppService.mainApp
                            let status = loginItem.status
                            if status == .enabled {
                                try? loginItem.unregister()
                            }
                            self.showRestartSheet()
                            NSApp.terminate(nil)
                        }
                    }
                }
            case .cancelled:
                break
            default:
                break
            }
        } else {
            AlertShow.showInfo(
                title: "Unable to uninstall AppLocker".localized,
                message: "You need to unlock all applications before Uninstalling".localized,
                style: .critical)
        }
    }

    @objc func checkUpdate() {
        let savedChannel = UserDefaults.standard.string(forKey: "updateChannel") ?? "Stable"
        let useBeta = (savedChannel == "Beta")
        AppUpdater.shared.manualCheckForUpdates(useBeta: useBeta)

        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in NSApp.windows {
                let cls = String(describing: type(of: window))
                if cls.contains("SU") || cls.contains("SPU") {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }

    @objc func launchAtLogin(_ sender: NSMenuItem) {
        Task {
            let loginItem = SMAppService.mainApp
            if sender.state == .on {
                try? await loginItem.unregister()
                sender.state = .off
            } else {
                try? loginItem.register()
                sender.state = .on
            }
        }
    }

    @objc func about() {
        // 1. Kích hoạt app
        NSApp.activate(ignoringOtherApps: true)

        // 2. Show about panel
        NSApp.orderFrontStandardAboutPanel(nil)

        // 3. Ép focus sau một tick
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                let cls = String(describing: type(of: window))
                if cls.contains("About") {
                    window.makeKey()                       // biến thành key window
                    window.makeKeyAndOrderFront(nil)       // bring lên
                    window.orderFrontRegardless()          // ép ra trước mọi thứ
                }
            }
        }
    }
}

extension NSApplication {
    static func autoCenterAllWindows() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                centerWindow(window)
            }
        }
    }

    private static func centerWindow(_ window: NSWindow) {
        if let screen = window.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            let size = window.frame.size
            let origin = CGPoint(
                x: screenFrame.midX - size.width/2,
                y: screenFrame.midY - size.height/2+50
            )
            window.setFrameOrigin(origin)
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

extension AppDelegate {
    func callUninstallHelper() {
        let conn = NSXPCConnection(
            machServiceName: "com.TranPhuong319.AppLockerHelper",
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: AppLockerHelperProtocol.self)
        conn.resume()

        if let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            // Ignore luôn vì sau khi uninstall helper sẽ tự kill
            Logfile.core.debug("XPC connection closed (expected): \(error.localizedDescription)")
        }) as? AppLockerHelperProtocol {
            proxy.uninstallHelper() { _, _ in
                // Fire-and-forget: không cần xử lý gì ở đây
            }
        }

        // Đóng connection ngay, tránh giữ reference thừa
        conn.invalidate()
    }
}

extension AppDelegate {
    func showRestartSheet() {
        let script = "tell application \"loginwindow\" to «event aevtrrst»"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        do {
            try task.run()
        } catch {
            print("Lỗi chạy osascript: \(error)")
        }
    }
}

extension AppDelegate: AppUpdaterBridgeDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
    
    func didFindUpdate(_ item: SUAppcastItem) {
        guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              item.displayVersionString.compare(current, options: .numeric) == .orderedDescending
        else {
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            Logfile.core.debug("Update \(item.displayVersionString) is not newer than current \(currentVersion)")
            return
        }

        pendingUpdate = item

        let content = UNMutableNotificationContent()
        content.title = "AppLocker Update Available".localized
        content.body = "Version %@ is ready".localized(with: item.displayVersionString)
        content.sound = UNNotificationSound.defaultCritical
        content.badge = nil

        // dùng identifier cố định, để click còn xoá đúng
        let request = UNNotificationRequest(
            identifier: notificationIndentifiers,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func didNotFindUpdate() {
        Logfile.core.debug("No update found (silent check)")
        pendingUpdate = nil
        NSApp.dockTile.badgeLabel = nil
        UNUserNotificationCenter.current().setBadgeCount(0)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationIndentifiers])
    }
}

// MARK: - Notification Handling
extension AppDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == notificationIndentifiers {
            // Mở bảng update Sparkle
            AppUpdater.shared.updaterController.checkForUpdates(nil)
            // Clear notification
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [notificationIndentifiers]
            )
        }
        completionHandler()
    }
}

