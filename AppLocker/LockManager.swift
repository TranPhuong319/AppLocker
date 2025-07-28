//
//

//  MARK: LockManager.swift

//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//

import AppKit
import Foundation

class LockedAppsManager: ObservableObject {
    @Published var lockedApps: [String] = []

    private var configFile: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("AppLocker", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appFolder.path) {
            try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }
        return appFolder.appendingPathComponent("config.plist")
    }

    private var currentBundleFile: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AppLocker/.current_bundle")
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style = .warning) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = style
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    init() {
        load()
    }

    func load() {
        if !FileManager.default.fileExists(atPath: configFile.path) {
            lockedApps = []
            save()
            return
        }
        do {
            let data = try Data(contentsOf: configFile)
            lockedApps = try PropertyListDecoder().decode([String].self, from: data)
        } catch {
            showAlert(title: "Lỗi", message: "Không thể load file cấu hình")
            lockedApps = []
        }
    }

    func save() {
        DispatchQueue.global(qos: .utility).async { [self] in
            let dirURL = configFile.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: configFile.path) {
                    _ = shell("chflags nouchg '\(configFile.path)'")
                }
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .xml // dùng XML plist
                let data = try encoder.encode(lockedApps)
                try data.write(to: configFile)
                
                // Chuyển sở hữu về root:wheel (yêu cầu chạy dưới quyền root)
                _ = shell("chown root:wheel '\(configFile.path)'")
                _ = shell("chflags uchg '\(configFile.path)'")
            } catch {
                showAlert(title: "Lỗi", message: "Không thể luu được cấu hình")
            }
        }
    }

    func toggleLock(for bundleIDs: [String]) {
        var allTasks: [String] = []
        var updatedLockedApps = lockedApps

        for bundleID in bundleIDs {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                print("⚠️ Không tìm thấy app: \(bundleID)")
                continue
            }

            let macOSDir = appURL.appendingPathComponent("Contents/MacOS")
            let execName: String

            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: macOSDir.path)
                if contents.count == 1 {
                    execName = contents[0]
                } else {
                    let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
                    let data = try Data(contentsOf: infoPlist)
                    if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                       let exec = plist["CFBundleExecutable"] as? String {
                        execName = exec
                    } else {
                        print("⚠️ Không thể đọc CFBundleExecutable từ Info.plist cho \(bundleID)")
                        continue
                    }
                }
            } catch {
                print("⚠️ Lỗi khi truy cập MacOS dir hoặc Info.plist: \(error)")
                continue
            }

            let origExe = macOSDir.appendingPathComponent(execName)
            let realExe = macOSDir.appendingPathComponent("\(execName).real")
            let currentMarker = currentBundleFile.path

            guard let stubURL = Bundle.main.url(forResource: "Launcher", withExtension: nil) else {
                print("⚠️ Không tìm thấy Launcher trong bundle")
                continue
            }

            let escapedBundleID = bundleID.replacingOccurrences(of: "'", with: "'\\''")

            if lockedApps.contains(bundleID) {
                // 🔓 Unlock
                allTasks.append(contentsOf: [
                    "[ -f '\(realExe.path)' ] || exit 1",
                    "rm -f '\(origExe.path)'",
                    "mv '\(realExe.path)' '\(origExe.path)'",
                    "chmod +x '\(origExe.path)'",
                    "rm -f '\(currentMarker)'",
                ])
                updatedLockedApps.removeAll { $0 == bundleID }
                print("🔓 Sẽ mở khóa \(bundleID)")
            } else {
                // 🔒 Lock
                allTasks.append(contentsOf: [
                    "echo '\(escapedBundleID)' > '\(currentMarker)'",
                    "mv '\(origExe.path)' '\(realExe.path)'",
                    "cp '\(stubURL.path)' '\(origExe.path)'",
                    "chmod +x '\(origExe.path)'",
                ])
                updatedLockedApps.append(bundleID)
                print("🔒 Sẽ khóa \(bundleID)")
            }
        }

        // ✅ Chạy toàn bộ task 1 lần duy nhất
        if !allTasks.isEmpty {
            if executeAdminTasks(allTasks) {
                DispatchQueue.main.async {
                    self.lockedApps = updatedLockedApps
                    self.save()
                    self.showAlert(title: "Thành công", message: "Đã xử lý \(bundleIDs.count) ứng dụng", style: .informational)
                }
            } else {
                print("⚠️ Không có ứng dụng nào được xử lý hoặc có lỗi xảy ra.")
            }
        }
    }

    func isLocked(_ bundleID: String) -> Bool {
        lockedApps.contains(bundleID)
    }

    @discardableResult
    private func executeAdminTasks(_ tasks: [String]) -> Bool {
        let script = tasks.joined(separator: " && ")
        let fullScript = "do shell script \"\(script)\" with administrator privileges"

        // ✅ Bọc các lệnh UI trong main thread
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            SettingsWindowController.shared?.makeKeyAndOrderFront(nil)
        }

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: fullScript) {
            let result = appleScript.executeAndReturnError(&error)

            if let error = error {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Lỗi yêu cầu quyền admin"
                    alert.informativeText = "Mật khẩu admin không đúng hoặc đã bị hủy. Chi tiết: \(error)"
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                print("❌ AppleScript error: \(error)")
                return false
            }

            print("✅ AppleScript executed: \(result.stringValue ?? "(no output)")")
            return true
        }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Lỗi thực thi AppleScript"
            alert.informativeText = "Không thể khởi tạo AppleScript."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        return false
    }

    @discardableResult
    func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/zsh"
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// import Foundation
// import AppKit
// import QuartzCore
// import LocalAuthentication
// import SwiftUI
//
// class LockManager: ObservableObject {
//    private var pendingTasks: [String] = []
//    @Published var lockedApps: [String] = []
//    private var currentlyAuthenticating: Set<String> = []
//    private var timer: Timer?
//
//    private var configFile: URL {
//        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
//        let appFolder = appSupport.appendingPathComponent("AppLocker", isDirectory: true)
//        if !FileManager.default.fileExists(atPath: appFolder.path) {
//            try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
//        }
//        return appFolder.appendingPathComponent("config.plist")
//    }
//
//    private var currentBundleFile: URL {
//        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
//        return appSupport.appendingPathComponent("AppLocker/.current_bundle")
//    }
//
//    init() {
//        load()
//    }
//
//    func loadConfig() {
//        let path = configFile.path
//        do {
//            let data = try Data(contentsOf: URL(fileURLWithPath: path))
//            let decoder = PropertyListDecoder()
//            let apps = try decoder.decode([String].self, from: data)
//            DispatchQueue.main.async {
//                self.lockedApps = apps
//            }
//        } catch {
//            print("❌ Không thể load cấu hình: \(error)")
//        }
//    }
//
//
//    func load() {
//        if let data = try? Data(contentsOf: configFile),
//           let apps = try? PropertyListDecoder().decode([String].self, from: data) {
//            lockedApps = apps
//        }
//    }
//
//    func toggleLock(for bundleID: String) {
//        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
//            print("⚠️ Không tìm thấy app: \(bundleID)")
//            return
//        }
//
//        let macOSDir = appURL.appendingPathComponent("Contents/MacOS")
//        let execName: String
//
//        do {
//            let contents = try FileManager.default.contentsOfDirectory(atPath: macOSDir.path)
//            if contents.count == 1 {
//                execName = contents[0]
//            } else {
//                let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
//                let data = try Data(contentsOf: infoPlist)
//                if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
//                   let exec = plist["CFBundleExecutable"] as? String {
//                    execName = exec
//                } else {
//                    print("⚠️ Không thể đọc CFBundleExecutable từ Info.plist")
//                    return
//                }
//            }
//        } catch {
//            print("⚠️ Lỗi khi truy cập MacOS dir hoặc Info.plist: \(error)")
//            return
//        }
//
//        let origExe = macOSDir.appendingPathComponent(execName)
//        let realExe = macOSDir.appendingPathComponent("\(execName).real")
//
//        guard let stubURL = Bundle.main.url(forResource: "Launcher", withExtension: nil) else {
//            print("⚠️ Không tìm thấy Launcher trong bundle")
//            return
//        }
//
//        if lockedApps.contains(bundleID) {
//            let tasks = [
//                "[ -f '\(realExe.path)' ] || exit 1",
//                "rm -f '\(origExe.path)'",
//                "mv '\(realExe.path)' '\(origExe.path)'",
//                "chmod +x '\(origExe.path)'",
//                "rm -f '\(currentBundleFile.path)'"
//            ]
//            pendingTasks.append(contentsOf: tasks)
//            lockedApps.removeAll { $0 == bundleID }
//        } else {
//            let escapedBundleID = bundleID.replacingOccurrences(of: "'", with: "'\\''")
//            let _ = try? escapedBundleID.write(to: URL(fileURLWithPath: "/tmp/current_bundle"), atomically: true, encoding: .utf8)
//
//            let tasks = [
//                "echo \(escapedBundleID) > '\(currentBundleFile.path)'",
//                "mv '\(origExe.path)' '\(realExe.path)'",
//                "cp '\(stubURL.path)' '\(origExe.path)'",
//                "chmod +x '\(origExe.path)'"
//            ]
//            pendingTasks.append(contentsOf: tasks)
//        }
//    }
//
//    func applyPendingChanges(for bundleID: String) {
//        do {
//            let encoder = PropertyListEncoder()
//            encoder.outputFormat = .xml
//            let data = try encoder.encode(self.lockedApps)
//
//            let configPath = self.configFile.path
//            let tempPath = NSTemporaryDirectory() + "applocker_config_temp.plist"
//            try data.write(to: URL(fileURLWithPath: tempPath))
//
//            let configTasks = [
//                "chflags nouchg '\(configPath)'",
//                "/bin/cp '\(tempPath)' '\(configPath)'",
//                "chflags uchg '\(configPath)'"
//            ]
//            pendingTasks.append(contentsOf: configTasks)
//
//            let success = executeAdminTasks(pendingTasks)
//            DispatchQueue.main.async {
//                let alert = NSAlert()
//                alert.alertStyle = .informational
//                alert.messageText = success ? "Thành công" : "Thất bại"
//                alert.informativeText = success
//                    ? "Thành công thực hiện tác vụ."
//                    : "Không thể áp dụng thay đổi. Vui lòng thử lại."
//
//                alert.runModal()
//            }
//
//            if success {
//                print("✅ Đã áp dụng thay đổi và lưu cấu hình")
//                self.load()
//                loadConfig()
//                lockedApps.append(bundleID)
//            } else {
//                print("❌ Không thể áp dụng thay đổi")
//            }
//
//        } catch {
//            DispatchQueue.main.async {
//                let alert = NSAlert()
//                alert.alertStyle = .critical
//                alert.messageText = "Lỗi"
//                alert.informativeText = "Lỗi khi luu cấu hình: \(error.localizedDescription)"
//                alert.runModal()
//            }
//            print("❌ Lỗi khi chuẩn bị lưu cấu hình: \(error)")
//        }
//
//        pendingTasks.removeAll()
//    }
//
//
//    func isLocked(_ bundleID: String) -> Bool {
//        lockedApps.contains(bundleID)
//    }
//
//    @discardableResult
//    private func executeAdminTasks(_ tasks: [String]) -> Bool {
//        let script = tasks.joined(separator: " && ")
//        let fullScript = "do shell script \"\(script)\" with administrator privileges"
//
//        var error: NSDictionary?
//        if let appleScript = NSAppleScript(source: fullScript) {
//            let result = appleScript.executeAndReturnError(&error)
//            if let error = error {
//                DispatchQueue.main.async {
//                    let alert = NSAlert()
//                    alert.messageText = "Lỗi yêu cầu quyền admin"
//                    alert.informativeText = "Mật khẩu admin không đúng hoặc đã bị hủy. Chi tiết: \(error)"
//                    alert.alertStyle = .critical
//                    alert.addButton(withTitle: "OK")
//                    alert.runModal()
//                }
//                print("❌ AppleScript error: \(error)")
//                return false
//            }
//
//            print("✅ AppleScript executed: \(result.stringValue ?? "(no output)")")
//            return true
//        }
//
//        DispatchQueue.main.async {
//            let alert = NSAlert()
//            alert.messageText = "Lỗi thực thi AppleScript"
//            alert.informativeText = "Không thể khởi tạo AppleScript."
//            alert.alertStyle = .critical
//            alert.addButton(withTitle: "OK")
//            alert.runModal()
//        }
//        return false
//    }
// }
//
