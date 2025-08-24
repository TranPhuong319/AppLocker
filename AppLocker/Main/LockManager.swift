//
//  LockManager.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//

import AppKit
import Foundation

class LockManager: ObservableObject {
    @Published var lockedApps: [String: LockedAppInfo] = [:]
    @Published var allApps: [InstalledApp] = []

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
    
    func getInstalledApps() -> [InstalledApp] {
        let appsDir = "/Applications"
        var apps: [InstalledApp] = []

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: appsDir),
            includingPropertiesForKeys: nil
        ) else { return apps }

        // Gom các app theo tên gốc (Telegram, Zoom, v.v.)
        var grouped: [String: [URL]] = [:]
        for appURL in contents where appURL.pathExtension == "app" {
            let baseName = appURL.deletingPathExtension()
                .lastPathComponent
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            grouped[baseName, default: []].append(appURL)
        }

        for (baseName, urls) in grouped {
            let hiddenApp = urls.first(where: { $0.lastPathComponent.hasPrefix(".") }) // .Telegram.app
            let launcherApp = urls.first(where: { !$0.lastPathComponent.hasPrefix(".") }) // Telegram.app

            var skipGroup = false
            if let hidden = hiddenApp, let launcher = launcherApp {
                // Kiểm tra marker trong Resources của launcher (launcher/Contents/Resources/<AppName>.app)
                let marker = launcher.appendingPathComponent("Contents/Resources/\(baseName).app")
                if FileManager.default.fileExists(atPath: marker.path) {
                    // Nếu có marker → đây là cặp "bị khóa"
                    skipGroup = true
                }
            }

            if skipGroup {
                // THAY VÌ tiếp tục bỏ qua cả 2, ta thêm 1 entry đại diện (launcher) vào allApps
                // để `lockedAppObjects` có thể tìm thấy app bị khóa và hiển thị.
                if let launcher = launcherApp {
                    // Ưu tiên lấy thông tin (bundleID / icon) từ bản thật (hidden) nếu có,
                    // còn không thì lấy từ launcher.
                    var displayBundleURL = launcher
                    if let hidden = hiddenApp {
                        // hidden là .Telegram.app — kiểm tra xem có thể load bundle từ hidden không
                        if FileManager.default.fileExists(atPath: hidden.path),
                           Bundle(url: hidden) != nil {
                            displayBundleURL = hidden
                        }
                    }

                    if let bundle = Bundle(url: displayBundleURL),
                       let bundleID = bundle.bundleIdentifier {
                        let name = launcher.deletingPathExtension().lastPathComponent
                        // Nếu dùng hidden để lấy icon, icon sẽ là icon của app thật
                        let icon = NSWorkspace.shared.icon(forFile: displayBundleURL.path)
                        icon.size = NSSize(width: 32, height: 32)

                        apps.append(InstalledApp(
                            name: name,
                            bundleID: bundleID,
                            icon: icon,
                            path: launcher.path // path phải là launcher path (đại diện)
                        ))
                    } else {
                        // Fallback: nếu không lấy được bundle từ hidden/launcher thì vẫn thêm launcher
                        let name = launcher.deletingPathExtension().lastPathComponent
                        let icon = NSWorkspace.shared.icon(forFile: launcher.path)
                        icon.size = NSSize(width: 32, height: 32)
                        apps.append(InstalledApp(name: name, bundleID: "", icon: icon, path: launcher.path))
                    }
                }
                // Đã xử lý group, tiếp tục vòng for tiếp theo
                continue
            }

            // Nếu không bị skip thì thêm từng app bình thường
            for appURL in urls {
                if let bundle = Bundle(url: appURL),
                   let bundleID = bundle.bundleIdentifier {
                    let name = appURL.deletingPathExtension().lastPathComponent
                    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                    icon.size = NSSize(width: 32, height: 32)
                    apps.append(InstalledApp(
                        name: name,
                        bundleID: bundleID,
                        icon: icon,
                        path: appURL.path
                    ))
                }
            }
        }

        // Debug
        #if DEBUG
        print("🔒 Locked Apps: \(lockedApps.keys)")
        print("📂 All Apps: \(allApps.map { $0.name })")
        print("getInstalledApps() -> \(apps.count) apps")
        for a in apps {
            print(" • \(a.name) | bundleID=\(a.bundleID) | path=\(a.path)")
        }
        #endif

        return apps
    }


    init() {
        load() // Load lockedApps trước
        self.allApps = getInstalledApps()
    }

    func load() {
        if !FileManager.default.fileExists(atPath: configFile.path) {
            lockedApps = [:]
            save()
            return
        }
        do {
            let data = try Data(contentsOf: configFile)
            lockedApps = try PropertyListDecoder().decode([String: LockedAppInfo].self, from: data)
        } catch {
            showAlert(title: "Error".localized, message: "Cannot load the configuration file".localized)
            lockedApps = [:]
        }
        for (key, value) in lockedApps {
            if !key.hasPrefix("/") {
                // Nếu là bundleID → tìm app theo bundleID để lấy path
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
                    lockedApps[appURL.path] = value
                    lockedApps.removeValue(forKey: key)
                }
            }
        }
    }
    
    func save() {
        let uid = getuid()
        let gid = getgid()
        DispatchQueue.global(qos: .utility).async { [self] in
            let dirURL = configFile.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                
                if FileManager.default.fileExists(atPath: configFile.path) {
                    let readfile: [[String: Any]] = [
                        ["command": "chflags", "args": ["nouchg", configFile.path]],
                        ["command": "chown", "args": ["\(uid):\(gid)", configFile.path]],
                    ]
                    if sendToHelperBatch(readfile){
                        Logfile.core.info("Unlocked successfully")
                    } else {
                        Logfile.core.error("Unlock unsuccessful")
                    }
                }

                let encoder = PropertyListEncoder()
                encoder.outputFormat = .xml
                let data = try encoder.encode(lockedApps)
                try data.write(to: configFile)
                
                let savefile: [[String: Any]] = [
                    ["command": "chown", "args": ["root:wheel", configFile.path]],
                    ["command": "chflags", "args": ["uchg", configFile.path]],
                ]
                if sendToHelperBatch(savefile){
                    Logfile.core.info("✅ File lock successful")
                } else {
                    Logfile.core.error("❌ File lock unsuccessful")
                }
            } catch {
                Logfile.core.error("Unable to save configuration")
            }
        }
    }

    func toggleLock(for paths: [String]) {
        for path in paths {
            let appURL = URL(fileURLWithPath: path)
            let appName = appURL.deletingPathExtension().lastPathComponent

            let uid = getuid()
            let gid = getgid()

            if let lockedInfo = lockedApps[path] {
                // 🔓 Unlock
                let disguisedAppName = lockedInfo.name
                let execFile = lockedInfo.execFile

                let disguisedAppPath = "/Applications/\(disguisedAppName).app"
                let hiddenApp = "/Applications/.\(disguisedAppName).app"
                let execPath = "\(hiddenApp)/Contents/MacOS/\(execFile)"

                let cmds: [[String: Any]] = [
                    ["command": "chflags", "args": ["nouchg", hiddenApp]],
                    ["command": "chflags", "args": ["nouchg", execPath]],
                    ["command": "chown", "args": ["\(uid):\(gid)", execPath]],
                    ["command": "rm", "args": ["-rf", disguisedAppPath]],
                    ["command": "mv", "args": [hiddenApp, disguisedAppPath]],
                    ["command": "touch", "args": [disguisedAppPath]],
                    ["command": "chflags", "args": ["nohidden", disguisedAppPath]],
                    ["command": "chmod", "args": ["755", "\(disguisedAppPath)/Contents/MacOS/\(execFile)"]],
                    ["command": "touch", "args": [disguisedAppPath]],
                ]

                if sendToHelperBatch(cmds) {
                    lockedApps.removeValue(forKey: path)
                    save()
                }

            } else {
                // 🔒 Lock
                guard let infoPlist = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                      let execName = infoPlist["CFBundleExecutable"] as? String,
                      let _ = infoPlist["CFBundleIdentifier"] as? String else {
                    Logfile.core.warning("⚠️ Cannot read info.plist for \(path, privacy: .public)")
                    continue
                }

                // Lấy iconName nếu có
                var iconName: String? = nil
                if let icon = infoPlist["CFBundleIconFile"] as? String {
                    iconName = icon.hasSuffix(".icns") ? String(icon.dropLast(5)) : icon
                }

                let launcherURL = Bundle.main.url(forResource: "Launcher", withExtension: "app")!
                let disguisedAppPath = "/Applications/\(appName).app"
                let hiddenApp = "/Applications/.\(appName).app"
                let launcherResources = "/Applications/Launcher.app/Contents/Resources/Locked"
                let markerPath = "\(disguisedAppPath)/Contents/Resources/\(appName).app"

                var cmds: [[String: Any]] = [
                    ["command": "cp", "args": ["-Rf", launcherURL.path, "/Applications/"]],
                    ["command": "mkdir", "args": ["-p", launcherResources]],
                    ["command": "mv", "args": [appURL.path, hiddenApp]],
                    ["command": "chmod", "args": ["000", "\(hiddenApp)/Contents/MacOS/\(execName)"]],
                    ["command": "chown", "args": ["root:wheel", "\(hiddenApp)/Contents/MacOS/\(execName)"]],
                    ["command": "chflags", "args": ["hidden", hiddenApp]],
                    ["command": "mv", "args": ["/Applications/Launcher.app", disguisedAppPath]],
                    ["command": "chflags", "args": ["uchg", "\(hiddenApp)/Contents/MacOS/\(execName)"]],
                    ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleIdentifier com.TranPhuong319.Launcher - \(appName)", "\(disguisedAppPath)/Contents/Info.plist"]],
                    ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleName \(appName)", "\(disguisedAppPath)/Contents/Info.plist"]],
                    ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleExecutable \(appName)", "\(disguisedAppPath)/Contents/Info.plist"]],
                    ["command": "mv", "args": ["\(disguisedAppPath)/Contents/MacOS/Launcher", "\(disguisedAppPath)/Contents/MacOS/\(appName)"]],
                    ["command": "touch", "args": [markerPath]],
                    ["command": "chown", "args": ["root:wheel", markerPath]],
                    ["command": "chflags", "args": ["uchg", markerPath]],
                    ["command": "touch", "args": [disguisedAppPath]],
                    
                ]

                // Nếu có icon thì thêm lệnh liên quan đến icon
                if let iconName = iconName {
                    cmds.insert(["command": "cp", "args": [appURL.appendingPathComponent("Contents/Resources/\(iconName).icns").path, "/Applications/Launcher.app/Contents/Resources/AppIcon.icns"]], at: 1)
                    cmds.append(["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconName", "\(disguisedAppPath)/Contents/Info.plist"]])
                } else {
                    // Nếu không có icon, chỉ xóa CFBundleIconFile trong launcher Info.plist nếu có
                    cmds.append(["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconFile", "\(disguisedAppPath)/Contents/Info.plist"]])
                    cmds.append(["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconName", "\(disguisedAppPath)/Contents/Info.plist"]])
                    cmds.append(["command": "rm", "args": ["-rf", "\(disguisedAppPath)/Contents/Resources/AppIcon.icns"]])
                }
                cmds.append(["command": "chflags", "args": ["uchg", hiddenApp]])
                cmds.append(["command": "touch", "args": [disguisedAppPath]])
                if sendToHelperBatch(cmds) {
                    lockedApps[path] = LockedAppInfo(name: appName, execFile: execName)
                    save()
                }
            }
        }
    }
    
    func sendToHelperBatch(_ commandList: [[String: Any]]) -> Bool {
        let conn = NSXPCConnection(machServiceName: "com.TranPhuong319.AppLockerHelper", options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: AppLockerHelperProtocol.self)
        conn.resume()

        let semaphore = DispatchSemaphore(value: 0)
        var result: Bool = false

        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            Logfile.core.error("❌ XPC error: \(error, privacy: .public)")
            Logfile.core.error("Error happened when executing orders. Details: \(error, privacy: .public)")
            result = false
            semaphore.signal()
        } as? AppLockerHelperProtocol

        proxy?.sendBatch(commandList) { success, message in
            if (success){
                Logfile.core.info("Success: \(message, privacy: .public)")
            } else {
                Logfile.core.error("Failure: \(message, privacy: .public)")
            }
            result = success
            semaphore.signal()
        }
        // Đợi phản hồi từ helper
        semaphore.wait()
        conn.invalidate()
        return result
    }
    
    func reloadAllApps() {
        DispatchQueue.global(qos: .background).async {
            let apps = self.getInstalledApps()
            DispatchQueue.main.async {
                self.allApps = apps
                
            }
        }
    }
    
    func isLocked(path: String) -> Bool {
        return lockedApps[path] != nil
    }
}

