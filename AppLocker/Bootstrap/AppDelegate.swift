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

var modeLock: String? = UserDefaults.standard.string(forKey: "selectedMode")
let plistName = "com.TranPhuong319.AppLocker.agent"

// MARK: AppDelegate.swift
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = AppDelegate()
    var statusItem: NSStatusItem?
    let helperIdentifier = "com.TranPhuong319.AppLocker.Helper"
    var pendingUpdate: SUAppcastItem?
    let notificationIndentifiers = "AppLockerUpdateNotification"
    var hotkey: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logfile.core.info("AppLocker v\(Bundle.main.fullVersion) starting...")
        
        Logfile.core.info("Setting up hotkey manager...")
        hotkey = HotKeyManager()
        
        Logfile.core.info("Checking kext signing status...")
        if isKextSigningDisabled() {
            if modeLock == nil {
                WelcomeWindowController.show()
                return
            } else {
                launchConfig(config: modeLock!)
            }
        } else {
            launchConfig(config: "Launcher")
        }
    }
}

extension AppDelegate {
    func manageAgent(plistName: String, action: AgentAction) {
        let agent = SMAppService.agent(plistName: "\(plistName).plist")
        
        do {
            switch action {
            case .install:
                if agent.status == .enabled {
                    Logfile.core.info("✅ Agent already registered: \(agent.status.description)")
                    return
                }
                try agent.register()
                Logfile.core.info("🚀 Agent registered successfully")
                
            case .uninstall:
                if agent.status == .enabled {
                    try agent.unregister()
                    Logfile.core.info("🧹 Agent unregistered successfully")
                } else {
                    Logfile.core.info("ℹ️ Agent not registered, skipping uninstall")
                }
                
            case .checkAndInstallifNeed:
                if agent.status != .enabled {
                    Logfile.core.info("⚠️ Agent not active, registering new one")
                    try agent.register()
                    NSApp.terminate(nil)
                }
            }
            
        } catch {
            let nsError = error as NSError
            Logfile.core.error("❌ Failed to manage agent: \(nsError.domain) - code: \(nsError.code) - \(nsError.localizedDescription)")
        }
    }
}

// MARK: - Mode Lock
extension AppDelegate {
    func launchConfig(config: String) {
        if config == "Launcher" {
            HelperInstaller.checkAndAlertBlocking(helperToolIdentifier: helperIdentifier)
        } else {
            // Đăng ký callback
            ExtensionInstaller.shared.onInstalled = {
                Logfile.core.info("[App] Starting XPC server after extension install")
                XPCServer.shared.start()
                Logfile.core.info("Starting menu bar and Notification")
                self.setupMenuBar()
                AppUpdater.shared.setBridgeDelegate(self)
                AppUpdater.shared.startTestAutoCheck()
                
                UNUserNotificationCenter.current().delegate = self
                UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { granted, error in
                    if let error = error { Logfile.core.error("Notification error: \(error, privacy: .public)") }
                }
                Logfile.core.info("Starting User state")
                SessionObserver.shared.start()
            }
            
            Logfile.core.info("Installing Endpoint Security extension...")
            // Chạy install
            ExtensionInstaller.shared.install()
        }
        
        Logfile.core.info("Setting up menu bar...")
        if let window = NSApp.windows.first {
            TouchBarManager.shared.apply(to: window, type: .mainWindow)
        }
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
        
        let infoItem = NSMenuItem(title: "AppLocker v\(Bundle.main.fullVersion)",
                                action: nil,
                                keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(.separator())
        
        if NSEvent.modifierFlags.contains(.option) {
            buildOptionMenu(for: menu)
        } else {
            buildNormalMenu(for: menu)
        }
    }

    private func buildNormalMenu(for menu: NSMenu) {
        let manageItem = NSMenuItem(title: "Manage the application list".localized,
                                    action: #selector(openListApp),
                                    keyEquivalent: "l")
        manageItem.keyEquivalentModifierMask = [.command,.shift]
        menu.addItem(manageItem)
        
        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AppLocker".localized,
                                action: #selector(quitApp),
                                keyEquivalent: "q"))
        #endif
    }

    private func buildOptionMenu(for menu: NSMenu) {
        menu.addItem(NSMenuItem(title: "Settings".localized,
                                action: #selector(openPreference),
                                keyEquivalent: ","))
        menu.addItem(.separator())

        if modeLock == "Launcher" {
            let launchItem = NSMenuItem(title: "Launch At Login".localized,
                                        action: #selector(launchAtLogin),
                                        keyEquivalent: "")
            launchItem.target = self
            launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            menu.addItem(launchItem)
        }
        
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
//        if modeLock == "Launcher"{
            NSApp.terminate(nil)
//        } else {
//            AuthenticationManager.authenticate(
//                reason: "authenticate to quit app".localized
//            ) { success, error in
//                DispatchQueue.main.async {
//                    if success {
//                        NSApp.terminate(nil)
//                    } else {
//                        Logfile.core.error("Error quiting app: \(error as NSObject?, privacy: .public)")
//                    }
//                }
//            }
//        }
    }

    @objc func openPreference() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.show()
    }

    @objc func uninstall() {
        Logfile.core.info("Uninstall Clicked")
        let manager = AppState.shared.manager
        NSApp.activate(ignoringOtherApps: true)

        if manager.lockedApps.isEmpty || modeLock == "ES" {
            let confirm = AlertShow.show(title: "Uninstall Applocker?".localized,
                                    message: "You are about to uninstall AppLocker. Please make sure that all apps are unlocked!%@Your Mac will restart after Successful Uninstall".localized(with: "\n\n"),
                                    style: .critical,
                                    buttons: ["Cancel".localized, "Uninstall".localized],
                                    cancelIndex: 0)
            
            switch confirm {
            case .button(index: 1, title: "Uninstall".localized):
                if modeLock == "Launcher" {
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
                } else {
                    ExtensionInstaller.shared.onUninstalled = {
                        self.manageAgent(plistName: plistName, action: .uninstall)
                        self.showRestartSheet()
                        NSApp.terminate(nil)
                    }
                    ExtensionInstaller.shared.uninstall()
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
            machServiceName: "com.TranPhuong319.AppLocker.Helper",
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
    
    func selfRemoveApp() {
        let bundlePath = Bundle.main.bundlePath
        let script = """
        rm -rf "\(bundlePath)"
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]

        do {
            try task.run()
            NSLog("🧹 App will remove itself at path: \(bundlePath)")
        } catch {
            NSLog("❌ Failed to start self-removal: \(error.localizedDescription)")
        }
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

extension AppDelegate {
    func restartApp(mode: String) {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        try? task.run()
        if modeLock != "Launcher" {
            manageAgent(plistName: plistName, action: .install)
        }
        // Thoát app hiện tại
        NSApp.terminate(nil)
    }
}
