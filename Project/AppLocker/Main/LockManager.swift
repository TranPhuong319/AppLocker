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
        let paths = ["/Applications"]
        var apps: [InstalledApp] = []

        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            ) else { continue }

            for appURL in contents where appURL.pathExtension == "app" {
                let resourceURL = appURL.appendingPathComponent("Contents/Applications")

                // ✅ Kiểm tra có file `.locked_<AppName>.app` không
                if let resourceContents = try? FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil),
                   let lockedAppFile = resourceContents.first(where: { $0.lastPathComponent.hasPrefix(".locked_") && $0.pathExtension == "app" }) {

                    // Lấy đường dẫn tới app gốc bị khoá thật
                    let realAppName = lockedAppFile.lastPathComponent.replacingOccurrences(of: ".locked_", with: "")
                    let realAppPath = resourceURL.appendingPathComponent(realAppName)
                    
                    if let bundle = Bundle(url: realAppPath),
                       let bundleID = bundle.bundleIdentifier {
                        
                        let name = lockedApps[bundleID]?.name ?? realAppName.replacingOccurrences(of: ".app", with: "")
                        let icon = NSWorkspace.shared.icon(forFile: realAppPath.path)
                        icon.size = NSSize(width: 16, height: 16)
                        
                        apps.append(InstalledApp(name: name, bundleID: bundleID, icon: icon, path: appURL.path))
                        continue // skip thêm lần nữa nếu đã nhận diện qua .locked_
                    }
                }

                // ✅ Nếu là app thường
                if let bundle = Bundle(url: appURL),
                   let bundleID = bundle.bundleIdentifier {
                    let name = appURL.deletingPathExtension().lastPathComponent
                    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                    icon.size = NSSize(width: 32, height: 32)
                    apps.append(InstalledApp(name: name, bundleID: bundleID, icon: icon, path: appURL.path))
                }
            }
        }

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
                let realAppPath = "\(disguisedAppPath)/Contents/Applications/\(disguisedAppName).app"
                let execPath = "\(realAppPath)/Contents/MacOS/\(execFile)"

//                let markerPathunlock = "\(disguisedAppPath)/Contents/Resources/.locked_\(disguisedAppName).app"

                let cmds: [[String: Any]] = [
                    ["command": "chflags", "args": ["nouchg", execPath]],
                    ["command": "chown", "args": ["\(uid):\(gid)", execPath]],
                    ["command": "mv", "args": [disguisedAppPath, "/Applications/Launcher.app"]],
                    ["command": "mv", "args": ["/Applications/Launcher.app/Contents/Applications/\(disguisedAppName).app", disguisedAppPath]],
                    ["command": "touch", "args": [disguisedAppPath]],
                    ["command": "rm", "args": ["-rf", "/Applications/Launcher.app"]],
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
                let launcherApplications = "/Applications/Launcher.app/Contents/Applications"
                let markerPath = "\(disguisedAppPath)/Contents/Applications/.locked_\(appName).app"

                var cmds: [[String: Any]] = [
                    ["command": "cp", "args": ["-Rf", launcherURL.path, "/Applications/"]],
                    ["command": "mkdir", "args": ["-p", launcherApplications]],
                    ["command": "mv", "args": [appURL.path, launcherApplications]],
                    ["command": "chmod", "args": ["000", "\(launcherApplications)/\(appName).app/Contents/MacOS/\(execName)"]],
                    ["command": "chown", "args": ["root:wheel", "\(launcherApplications)/\(appName).app/Contents/MacOS/\(execName)"]],
                    ["command": "chflags", "args": ["hidden", "\(launcherApplications)/\(appName).app"]],
                    ["command": "mv", "args": ["/Applications/Launcher.app", disguisedAppPath]],
                    ["command": "chflags", "args": ["uchg", "\(disguisedAppPath)/Contents/Applications/\(appName).app/Contents/MacOS/\(execName)"]],
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


    func isLocked(path: String) -> Bool {
        return lockedApps[path] != nil
    }
}

