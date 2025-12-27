//
//  AppDelegate.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//
//  EN: App lifecycle, menu bar, updates, and integration with ES/Launcher modes.
//  VI: Vòng đời ứng dụng, menu bar, cập nhật, và tích hợp với chế độ ES/Launcher.
//

import AppKit
import LocalAuthentication
import Security
import ServiceManagement
import Foundation
import SwiftUI
import UserNotifications
import Sparkle

// EN: Possible actions for the agent (login item) management.
// VI: Các hành động có thể cho quản lý agent (login item).
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

extension AppDelegate {
    // EN: Register/unregister/check the login item agent.
    // VI: Đăng ký/hủy/kiểm tra agent đăng nhập.
    func manageAgent(plistName: String, action: AgentAction) {
        let agent = SMAppService.agent(plistName: "\(plistName).plist")

        do {
            switch action {
            case .install:
                if agent.status == .enabled {
                    Logfile.core.info("Agent already registered: \(agent.status.description)")
                    return
                }
                try agent.register()
                Logfile.core.info("Agent registered successfully")

            case .uninstall:
                if agent.status == .enabled {
                    try agent.unregister()
                    Logfile.core.info("Agent unregistered successfully")
                } else {
                    Logfile.core.info("Agent not registered, skipping uninstall")
                }

            case .checkAndInstallifNeed:
                if agent.status != .enabled {
                    Logfile.core.info("Agent not active, registering new one")
                    try agent.register()
                    NSApp.terminate(nil)
                }
            }

        } catch {
            let nsError = error as NSError
            Logfile.core.error("Failed to manage agent: \(nsError.domain) - code: \(nsError.code) - \(nsError.localizedDescription)")
        }
    }
}

// MARK: - Mode Lock / Chế độ khóa
extension AppDelegate {
    func launchConfig(config: AppMode) {
        if config == .launcher {
            HelperInstaller.checkAndAlertBlocking(helperToolIdentifier: helperIdentifier)
        } else if config == .es {
            // EN: Register callback after the ES extension is installed.
            // VI: Đăng ký callback sau khi cài extension ES.
            ExtensionInstaller.shared.onInstalled = {
                Logfile.core.info("[App] Starting XPC server after extension install")
                XPCServer.shared.start()

                Logfile.core.info("Starting menu bar and Notification")
                self.setupMenuBar()

                AppUpdater.shared.setBridgeDelegate(self)
                AppUpdater.shared.startTestAutoCheck()

                UNUserNotificationCenter.current().delegate = self
                UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { _, error in
                    if let error = error { Logfile.core.error("Notification error: \(error, privacy: .public)") }
                }

                Logfile.core.info("Starting User state")
                SessionObserver.shared.start()

                Logfile.core.info("Setting up hotkey manager...")
                self.hotkey = HotKeyManager()

                Logfile.core.info("Setting up Touch Bar...")
                if let window = NSApp.windows.first {
                    TouchBarManager.shared.apply(to: window, type: .mainWindow)
                }
            }

            Logfile.core.info("Installing Endpoint Security extension...")
            ExtensionInstaller.shared.install()
        }
    }
}

// MARK: - Menu Bar / Thanh menu
extension AppDelegate: NSMenuDelegate {
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "AppLocker")

            button.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22)
            ])
        }

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
        manageItem.keyEquivalentModifierMask = [.command, .shift]
        manageItem.image = NSImage(systemSymbolName: "lock.app.dashed", accessibilityDescription: nil)
        menu.addItem(manageItem)

        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AppLocker".localized,
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        #endif
    }

    private func buildOptionMenu(for menu: NSMenu) {
        menu.addItem(NSMenuItem(title: "Settings".localized,
                                action: #selector(openSettings),
                                keyEquivalent: ","))
        menu.addItem(.separator())

        if modeLock == .launcher {
            let launchItem = NSMenuItem(title: "Launch At Login".localized,
                                        action: #selector(launchAtLogin),
                                        keyEquivalent: "")
            launchItem.target = self
            launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            menu.addItem(launchItem)
        }

        let updateItem = NSMenuItem(title: "Check for Updates...".localized,
                                action: #selector(checkUpdate),
                                keyEquivalent: "")
        updateItem.image = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90",
                                   accessibilityDescription: nil)
        menu.addItem(updateItem)
        let aboutItem = NSMenuItem(title: "About AppLocker".localized,
                                action: #selector(about),
                                keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(title: "Uninstall AppLocker".localized,
                                       action: #selector(uninstall),
                                       keyEquivalent: "")
        uninstallItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(uninstallItem)

        let resetItem = NSMenuItem(title: "Reset AppLocker".localized,
                                   action: #selector(resetApp),
                                   keyEquivalent: "")
        resetItem.image = NSImage(systemSymbolName: "arrow.counterclockwise.circle", accessibilityDescription: nil)

        // EN: Alternate item (Option+Shift) to replace Uninstall.
        // VI: Mục thay thế (Option+Shift) để thay thế Uninstall.
        resetItem.keyEquivalentModifierMask = NSEvent.ModifierFlags([.option, .shift])
        resetItem.isAlternate = true

        menu.addItem(resetItem)
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

// MARK: - App Actions / Hành động ứng dụng
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

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.show()
    }

    @objc func uninstall() {
        Logfile.core.info("Uninstall Clicked")
        let manager = AppState.shared.manager
        NSApp.activate(ignoringOtherApps: true)

        if manager.lockedApps.isEmpty || modeLock == .es {
            let confirm = AlertShow.show(title: "Uninstall Applocker?".localized,
                                         message: "You are about to uninstall AppLocker. Please make sure that all apps are unlocked!%@Your Mac will restart after Successful Uninstall".localized(with: "\n\n"),
                                         style: .critical,
                                         buttons: ["Cancel".localized, "Uninstall".localized],
                                         cancelIndex: 0)

            switch confirm {
            case .button(index: 1, title: "Uninstall".localized):
                switch modeLock {
                case .es:
                    ExtensionInstaller.shared.onUninstalled = {
                        self.manageAgent(plistName: plistName, action: .uninstall)
                        self.removeConfig()
                        self.selfRemoveApp()
                        self.showRestartSheet()
                        NSApp.terminate(nil)
                    }
                    ExtensionInstaller.shared.uninstall()
                case .launcher:
                    AuthenticationManager.authenticate(
                        reason: "uninstall the application".localized
                    ) { success, _ in
                        DispatchQueue.main.async {
                            if success {
                                self.callUninstallHelper()
                                let loginItem = SMAppService.mainApp
                                let status = loginItem.status
                                if status == .enabled {
                                    try? loginItem.unregister()
                                }
                                _ = HelperInstaller.manageHelperTool(
                                    action: .uninstall, helperToolIdentifier: self.helperIdentifier
                                )
                                self.selfRemoveApp()
                                self.removeConfig()
                                self.showRestartSheet()
                                NSApp.terminate(nil)
                            }
                        }
                    }
                case nil:
                    break
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

    @objc func resetApp() {
        Logfile.core.info("Reset App Clicked")
        NSApp.activate(ignoringOtherApps: true)
        let confirm = AlertShow.show(title: "Reset AppLocker".localized,
                                     message:
                                        """
                                        This operation will delete all settings including the list of locked applications. After successful reset, the application will be reopened.

                                        Do you want to continue?
                                        """.localized,
                                     style: .critical,
                                     buttons: ["Cancel".localized, "Reset".localized],
                                     cancelIndex: 0)
        switch confirm {
        case .button(index: 1, title: "Reset".localized):
            switch modeLock {
            case .launcher:
                let loginItem = SMAppService.mainApp
                let status = loginItem.status
                if status == .enabled {
                    try? loginItem.unregister()
                }
                removeConfig()
                _ = HelperInstaller.manageHelperTool(
                    action: .uninstall, helperToolIdentifier: helperIdentifier
                )
                restartApp(mode: nil)
            case .es:
                ExtensionInstaller.shared.onUninstalled = {
                    self.removeConfig()
                    self.manageAgent(plistName: plistName, action: .uninstall)
                    modeLock = nil
                    self.restartApp(mode: modeLock)
                }
                ExtensionInstaller.shared.uninstall()
            case nil:
                break
            }

        default:
            break
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
        // EN: 1) Activate app
        // VI: 1) Kích hoạt ứng dụng
        NSApp.activate(ignoringOtherApps: true)

        // EN: 2) Show standard about panel
        // VI: 2) Hiển thị bảng About chuẩn
        NSApp.orderFrontStandardAboutPanel(nil)

        // EN: 3) Force focus after a short delay
        // VI: 3) Ép focus sau một khoảng ngắn
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                let cls = String(describing: type(of: window))
                if cls.contains("About") {
                    window.makeKey()
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
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
            // EN: Ignore errors because helper will terminate itself after uninstall.
            // VI: Bỏ qua lỗi vì helper sẽ tự thoát sau khi gỡ cài đặt.
            Logfile.core.debug("XPC connection closed (expected): \(error.localizedDescription)")
        }) as? AppLockerHelperProtocol {
            proxy.uninstallHelper { _, _ in
                // EN: Fire-and-forget.
                // VI: Gửi và quên.
            }
        }

        // EN: Close connection immediately to avoid holding references.
        // VI: Đóng kết nối ngay để tránh giữ tham chiếu thừa.
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
            Logfile.core.info("App will remove itself at path: \(bundlePath)")
        } catch {
            Logfile.core.error("Failed to start self-removal: \(error.localizedDescription)")
        }
    }

    func removeConfig() {
        let fileManager = FileManager.default

        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let appFolderURL = appSupportURL.appendingPathComponent("AppLocker")

        do {
            if fileManager.fileExists(atPath: appFolderURL.path) {
                try fileManager.removeItem(at: appFolderURL)
                Logfile.core.info("The configuration folder has been successfully deleted.")

                let domain = Bundle.main.bundleIdentifier!
                UserDefaults.standard.removePersistentDomain(forName: domain)
                UserDefaults.standard.synchronize()

            }
        } catch {
            Logfile.core.error("Error deleting folder: \(error.localizedDescription, privacy: .public)")
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

        // EN: Use a fixed identifier to remove the correct notification when tapped.
        // VI: Dùng định danh cố định để xoá đúng thông báo khi người dùng bấm.
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

// MARK: - Notification Handling / Xử lý thông báo
extension AppDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == notificationIndentifiers {
            // EN: Open Sparkle update window.
            // VI: Mở cửa sổ cập nhật của Sparkle.
            AppUpdater.shared.updaterController.checkForUpdates(nil)
            // EN: Clear the delivered notification.
            // VI: Xoá thông báo đã gửi.
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [notificationIndentifiers]
            )
        }
        completionHandler()
    }
}

extension AppDelegate {
    func restartApp(mode: AppMode?) {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", path]
        try? task.run()
        if mode == .es {
            manageAgent(plistName: plistName, action: .install)
        }
        // EN: Terminate current app after relaunch.
        // VI: Thoát ứng dụng hiện tại sau khi khởi chạy lại.
        NSApp.terminate(nil)
    }
}
