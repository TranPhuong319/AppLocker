//
//

//  MARK: LockManager.swift

//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
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
                let resourceURL = appURL.appendingPathComponent("Contents/Resources")

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
                        icon.size = NSSize(width: 32, height: 32)
                        
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
            showAlert(title: "Lỗi", message: "Không thể load file cấu hình")
            lockedApps = [:]
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
                        print("Thành công mở khoá")
                    } else {
                        print("Mở khoá không thành công")
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
                    print("✅ Thành công khoá file")
                } else {
                    print("❌ Khoá file không thành công")
                }
            } catch {
                showAlert(title: "Lỗi", message: "Không thể lưu được cấu hình")
            }
        }
    }

    func toggleLock(for bundleIDs: [String]) {
        for bundleID in bundleIDs {
            let appURL: URL
            if let info = lockedApps[bundleID] {
                // App đã bị khoá → dựng lại đường dẫn theo Name đã lưu
                let disguisedAppPath = "/Applications/\(info.name).app"
                appURL = URL(fileURLWithPath: disguisedAppPath)
            } else {
                // App chưa bị khoá → lấy theo bundle ID
                guard let foundURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                    print("⚠️ Không tìm thấy app: \(bundleID)")
                    continue
                }
                appURL = foundURL
            }

            let uid = getuid()
            let gid = getgid()

            if let lockedInfo = lockedApps[bundleID] {
                // 🔓 Unlock - đọc từ config
                let disguisedAppName = lockedInfo.name
                let execFile = lockedInfo.execFile

                let disguisedAppPath = "/Applications/\(disguisedAppName).app"
                let realAppPath = "\(disguisedAppPath)/Contents/Resources/\(disguisedAppName).app"
                let execPath = "\(realAppPath)/Contents/MacOS/\(execFile)"
                let markerPathunlock = "\(disguisedAppPath)/Contents/Resources/.locked_\(disguisedAppName).app"

                let cmds: [[String: Any]] = [
                    ["command": "chflags", "args": ["nouchg", execPath]],
                    ["command": "chown", "args": ["\(uid):\(gid)", execPath]],
                    ["command": "mv", "args": [disguisedAppPath, "/Applications/Launcher.app"]],
                    ["command": "mv", "args": ["/Applications/Launcher.app/Contents/Resources/\(disguisedAppName).app", disguisedAppPath]],
                    
                    ["command": "rm", "args": ["-rf", "/Applications/Launcher.app"]],
                    ["command": "chflags", "args": ["nohidden", disguisedAppPath]],
                    ["command": "chmod", "args": ["755", "\(disguisedAppPath)/Contents/MacOS/\(execFile)"]],
                    ["command": "touch", "args": ["/Applications/\(disguisedAppName).app"]],
//                    ["command": "chflags", "args": ["nouchg", markerPathunlock]],
//                    ["command": "chown", "args": ["\(uid);\(gid)", markerPathunlock]],                ]
                ]
                if sendToHelperBatch(cmds) {
                    lockedApps.removeValue(forKey: bundleID)
                    save()
                }

            } else {
                // 🔒 Lock - đọc từ Info.plist gốc
                guard let infoPlist = try? NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist"), error: ()) as? [String: Any],
                      let execName = infoPlist["CFBundleExecutable"] as? String,
                      var iconName = infoPlist["CFBundleIconFile"] as? String,
                      let appName = infoPlist["CFBundleName"] as? String else {
                    print("⚠️ Không thể đọc Info.plist cho \(bundleID)")
                    continue
                }
                
                // Xoá phần đuôi .icns nếu có
                if iconName.hasSuffix(".icns") {
                    iconName = String(iconName.dropLast(5))
                }
                
                let bundle = "com.TranPhuong319.Launcher - \(appName)"

                let launcherURL = Bundle.main.url(forResource: "Launcher", withExtension: "app")!
                let disguisedAppPath = "/Applications/\(appName).app"
                let launcherResources = "/Applications/Launcher.app/Contents/Resources"
                let markerPath = "/Applications/\(appName).app/Contents/Resources/.locked_\(appName).app"

                let cmds: [[String: Any]] = [
                    ["command": "cp", "args": ["-Rf", launcherURL.path, "/Applications/"]],
                    ["command": "cp", "args": [appURL.appendingPathComponent("Contents/Resources/\(iconName).icns").path, "\(launcherResources)/AppIcon.icns"]],
                    ["command": "mv", "args": [appURL.path, launcherResources]],
                    ["command": "chmod", "args": ["000", "\(launcherResources)/\(appName).app/Contents/MacOS/\(execName)"]],
                    ["command": "chown", "args": ["root:wheel", "\(launcherResources)/\(appName).app/Contents/MacOS/\(execName)"]],
                    ["command": "chflags", "args": ["hidden", "\(launcherResources)/\(appName).app"]],
                    ["command": "mv", "args": ["/Applications/Launcher.app", disguisedAppPath]],
                    ["command": "chflags", "args": ["uchg", "\(disguisedAppPath)/Contents/Resources/\(appName).app/Contents/MacOS/\(execName)"]],
                    ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleIdentifier \(bundle)", "\(disguisedAppPath)/Contents/Info.plist"]],
                    ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconName", "\(disguisedAppPath)/Contents/Info.plist"]],
                    ["command": "touch", "args": ["/Applications/\(appName).app"]],
                    ["command": "touch", "args": [markerPath]],
                    ["command": "chown", "args": ["root:wheel", markerPath]],
                    ["command": "chflags", "args": ["uchg", markerPath]],
                ]

                if sendToHelperBatch(cmds) {
                    lockedApps[bundleID] = LockedAppInfo(name: appName, execFile: execName)
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
        for cmd in commandList {
            if let args = cmd["args"] as? [String] {
                for path in args {
                    if path.hasPrefix("/") && !FileManager.default.fileExists(atPath: path) {
                        print("⚠️ File không tồn tại: \(path)")
                    }
                }
            }
        }

        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            print("❌ XPC error: \(error)")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Lỗi"
                alert.informativeText = "Lỗi đã xảy ra khi thực thi lệnh. Chi tiết: \(error)"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            result = false
            semaphore.signal()
        } as? AppLockerHelperProtocol

        proxy?.sendBatch(commandList) { success, message in
            print(success ? "✅ Thành công:" : "❌ Thất bại:", message)
            result = success
            semaphore.signal()
        }

        // Đợi phản hồi từ helper
        semaphore.wait()
        conn.invalidate()
        return result
    }


    func isLocked(_ bundleID: String) -> Bool {
        lockedApps[bundleID] != nil
    }
}

