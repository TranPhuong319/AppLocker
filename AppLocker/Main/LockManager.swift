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
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: appsDir),
            includingPropertiesForKeys: nil
        ) else { return [] }

        let grouped = groupAppsByBaseName(contents)
        var apps: [InstalledApp] = []

        for (baseName, urls) in grouped {
            if let lockedApp = processLockedGroup(baseName: baseName, urls: urls) {
                apps.append(lockedApp)
            } else {
                apps.append(contentsOf: processNormalGroup(urls: urls))
            }
        }
        #if DEBUG
            logInstalledApps(apps)
        #endif
        return apps
    }

    // MARK: - Helpers

    private func groupAppsByBaseName(_ contents: [URL]) -> [String: [URL]] {
        var grouped: [String: [URL]] = [:]
        for appURL in contents where appURL.pathExtension == "app" {
            let baseName = appURL.deletingPathExtension()
                .lastPathComponent
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            grouped[baseName, default: []].append(appURL)
        }
        return grouped
    }

    private func processLockedGroup(baseName: String, urls: [URL]) -> InstalledApp? {
        let hiddenApp = urls.first(where: { $0.lastPathComponent.hasPrefix(".") })
        let launcherApp = urls.first(where: { !$0.lastPathComponent.hasPrefix(".") })

        guard let launcher = launcherApp, hiddenApp != nil else { return nil }

        let marker = launcher.appendingPathComponent("Contents/Resources/\(baseName).app")
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }

        // Ưu tiên lấy bundle từ hidden, fallback launcher
        var displayBundleURL = launcher
        if let hidden = hiddenApp,
           FileManager.default.fileExists(atPath: hidden.path),
           Bundle(url: hidden) != nil {
            displayBundleURL = hidden
        }

        return makeInstalledApp(from: displayBundleURL, fallbackLauncher: launcher)
    }

    private func processNormalGroup(urls: [URL]) -> [InstalledApp] {
        urls.compactMap { makeInstalledApp(from: $0, fallbackLauncher: nil) }
    }

    private func makeInstalledApp(from url: URL, fallbackLauncher: URL?) -> InstalledApp? {
        if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
            let name = (fallbackLauncher ?? url).deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            return InstalledApp(name: name, bundleID: bundleID, icon: icon, path: (fallbackLauncher ?? url).path)
        } else if let launcher = fallbackLauncher {
            // fallback nếu không load được bundle
            let name = launcher.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: launcher.path)
            icon.size = NSSize(width: 32, height: 32)
            return InstalledApp(name: name, bundleID: "", icon: icon, path: launcher.path)
        }
        return nil
    }

    #if DEBUG
    private func logInstalledApps(_ apps: [InstalledApp]) {
        print("getInstalledApps() -> \(apps.count) apps")
        for app in apps {
            print(" • \(app.name) | bundleID=\(app.bundleID) | path=\(app.path)")
        }
    }
    #endif

    init() {
        load() // Load lockedApps trước
        self.allApps = getInstalledApps()
    }

    func load() {
        // Nếu config.plist chưa tồn tại, khởi tạo rỗng
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            lockedApps = [:]
            save()
            return
        }

        do {
            let data = try Data(contentsOf: configFile)
            // Giải mã plist thành dictionary [String: LockedAppInfo]
            lockedApps = try PropertyListDecoder().decode([String: LockedAppInfo].self, from: data)
        } catch {
            showAlert(title: "Error".localized, message: "Cannot load the configuration file".localized)
            lockedApps = [:]
        }

        // ✅ Với path tuyệt đối, không cần check bundleID cũ
        // Xử lý bổ sung: loại bỏ key không hợp lệ (nếu có)
        for key in lockedApps.keys {
            if !FileManager.default.fileExists(atPath: key) {
                lockedApps.removeValue(forKey: key)
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
                        [
                            "do":   ["command": "chflags", "args": ["nouchg", configFile.path]],
                            "undo": ["command": "chflags", "args": ["uchg", configFile.path]]
                        ],
                        [
                            "do":   ["command": "chown", "args": ["\(uid):\(gid)", configFile.path]],
                            "undo": ["command": "chown", "args": ["root:wheel", configFile.path]]
                        ]
                    ]

                    if sendToHelperBatch(readfile) {
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
                    [
                        "do":   ["command": "chown", "args": ["root:wheel", configFile.path]],
                        "undo": ["command": "chown", "args": ["\(uid):\(gid)", configFile.path]] // trả về chủ sở hữu gốc
                    ],
                    [
                        "do":   ["command": "chflags", "args": ["uchg", configFile.path]],
                        "undo": ["command": "chflags", "args": ["nouchg", configFile.path]] // gỡ immutable flag
                    ]
                ]

                if sendToHelperBatch(savefile) {
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
        var didChange = false

        for path in paths {
            let appURL = URL(fileURLWithPath: path)
            let appName = appURL.deletingPathExtension().lastPathComponent
            let baseDir = appURL.deletingLastPathComponent().path
            let disguisedAppPath = "\(baseDir)/\(appName).app"
            let hiddenApp = "\(baseDir)/.\(appName).app"
            let launcherResources = "\(baseDir)/Launcher.app/Contents/Resources/Locked"
            let backupDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/AppLocker/Backups/\(appName)").path
            let markerApp = "\(baseDir)/\(appName).app/Contents/Resources/\(appName).app"

            let uid = getuid()
            let gid = getgid()
            
            do {
                try FileManager.default.createDirectory(
                    atPath: backupDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                print("✅ Tạo thư mục thành công: \(backupDir)")
            } catch {
                print("❌ Lỗi tạo thư mục: \(error.localizedDescription)")
            }

            if let lockedInfo = lockedApps[path] {
                // 🔓 Unlock
                let execPath = "\(hiddenApp)/Contents/MacOS/\(lockedInfo.execFile)"

                let unlock: [[String: Any]] = [
                    [
                        "do":   ["command": "chflags", "args": ["nouchg", hiddenApp]],
                        "undo": ["command": "chflags", "args": ["uchg", hiddenApp]]
                    ],
                    [
                        "do":   ["command": "chflags", "args": ["nouchg", execPath]],
                        "undo": ["command": "chflags", "args": ["uchg", execPath]]
                    ],
                    [
                        "do":   ["command": "chown", "args": ["\(uid):\(gid)", execPath]],
                        "undo": ["command": "chown", "args": ["root:wheel", execPath]]
                    ],
                    [
                        "do":   ["command": "rm", "args": ["-rf", disguisedAppPath]],
                        "undo": ["command": "cp", "args": ["-Rf", "\(backupDir)/\(appName).app", baseDir]]
                    ],
                    [
                        "do":   ["command": "mv", "args": [hiddenApp, disguisedAppPath]],
                        "undo": ["command": "mv", "args": [disguisedAppPath, hiddenApp]]
                    ],
                    [
                        "do":   ["command": "touch", "args": [disguisedAppPath]],
                        "undo": [:] // touch không cần rollback
                    ],
                    [
                        "do":   ["command": "chflags", "args": ["nohidden", disguisedAppPath]],
                        "undo": ["command": "chflags", "args": ["hidden", disguisedAppPath]]
                    ],
                    [
                        "do":   ["command": "chmod", "args": ["755", "\(disguisedAppPath)/Contents/MacOS/\(lockedInfo.execFile)"]],
                        "undo": ["command": "chmod", "args": ["000", "\(disguisedAppPath)/Contents/MacOS/\(lockedInfo.execFile)"]] // khôi phục về trạng thái bị lock
                    ],
                    [
                        "do":   ["command": "touch", "args": [disguisedAppPath]],
                        "undo": [:]
                    ],
                    [
                        "do":   ["command": "rm", "args": ["-rf", backupDir]],
                    ]
                ]

                if sendToHelperBatch(unlock) {
                    didChange = true
                    DispatchQueue.main.async{ [self] in
                        lockedApps.removeValue(forKey: path)
                    }
                }

            } else {
                // 🔒 Lock
                guard let infoPlist = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                      let execName = infoPlist["CFBundleExecutable"] as? String else {
                    Logfile.core.warning("⚠️ Cannot read info.plist for \(path, privacy: .public)")
                    continue
                }

                var iconName: String?
                if let icon = infoPlist["CFBundleIconFile"] as? String {
                    iconName = icon.hasSuffix(".icns") ? String(icon.dropLast(5)) : icon
                }

                let launcherURL = Bundle.main.url(forResource: "Launcher", withExtension: "app")!

                var lock: [[String: Any]] = [
                    [
                        "do":   ["command": "cp", "args": ["-Rf", launcherURL.path, baseDir]],
                        "undo": ["command": "rm", "args": ["-rf", "\(baseDir)/Launcher.app"]]
                    ],
                    [
                        "do":   ["command": "mkdir", "args": ["-p", launcherResources]],
                        "undo": ["command": "rm", "args": ["-rf", launcherResources]]
                    ],
                    [
                        "do":   ["command": "mv", "args": [appURL.path, hiddenApp]],
                        "undo": ["command": "mv", "args": [hiddenApp, appURL.path]]
                    ],
                    [
                        "do":   ["command": "chmod", "args": ["000", "\(hiddenApp)/Contents/MacOS/\(execName)"]],
                        "undo": ["command": "chmod", "args": ["755", "\(hiddenApp)/Contents/MacOS/\(execName)"]]
                    ],
                    [
                        "do":   ["command": "chown", "args": ["root:wheel", "\(hiddenApp)/Contents/MacOS/\(execName)"]],
                        "undo": ["command": "chown", "args": ["\(NSUserName()):staff", "\(hiddenApp)/Contents/MacOS/\(execName)"]] // trả về owner gốc user
                    ],
                    [
                        "do":   ["command": "chflags", "args": ["hidden", hiddenApp]],
                        "undo": ["command": "chflags", "args": ["nohidden", hiddenApp]]
                    ],
                    [
                        "do":   ["command": "mv", "args": ["\(baseDir)/Launcher.app", disguisedAppPath]],
                        "undo": ["command": "mv", "args": [disguisedAppPath, "\(baseDir)/Launcher.app"]]
                    ],
                    [
                        "do":   ["command": "chflags", "args": ["uchg", "\(hiddenApp)/Contents/MacOS/\(execName)"]],
                        "undo": ["command": "chflags", "args": ["nouchg", "\(hiddenApp)/Contents/MacOS/\(execName)"]]
                    ],
                    [
                        "do":   ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleIdentifier com.TranPhuong319.Launcher-\(appName)", "\(disguisedAppPath)/Contents/Info.plist"]],
                        "undo": ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIdentifier", "\(disguisedAppPath)/Contents/Info.plist"]]
                    ],
                    [
                        "do":   ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleName \(appName)", "\(disguisedAppPath)/Contents/Info.plist"]],
                        "undo": ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleName", "\(disguisedAppPath)/Contents/Info.plist"]]
                    ],
                    [
                        "do":   ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleExecutable \(appName)", "\(disguisedAppPath)/Contents/Info.plist"]],
                        "undo": ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleExecutable Launcher", "\(disguisedAppPath)/Contents/Info.plist"]]
                    ],
                    [
                        "do":   ["command": "mv", "args": ["\(disguisedAppPath)/Contents/MacOS/Launcher", "\(disguisedAppPath)/Contents/MacOS/\(appName)"]],
                        "undo": ["command": "mv", "args": ["\(disguisedAppPath)/Contents/MacOS/\(appName)", "\(disguisedAppPath)/Contents/MacOS/Launcher"]]
                    ],
                    [
                        "do":   ["command": "touch", "args": [launcherURL.path]],
                        "undo": ["command": "rm", "args": ["-rf", "\(baseDir)/Launcher.app"]]
                    ],
                    [
                        "do":   ["command": "touch", "args": [markerApp]],
                        "undo": [:]
                    ]
                ]

                // Icon handling
                if let iconName = iconName {
                    lock.insert([
                        "do":   ["command": "cp",
                                 "args": [appURL.appendingPathComponent("Contents/Resources/\(iconName).icns").path,
                                          "\(baseDir)/Launcher.app/Contents/Resources/AppIcon.icns"]],
                        "undo": ["command": "rm", "args": ["-f", "\(baseDir)/Launcher.app/Contents/Resources/AppIcon.icns"]]
                    ], at: 1)
                    lock.append([
                        "do":   ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconName", "\(disguisedAppPath)/Contents/Info.plist"]],
                        "undo": ["command": "PlistBuddy", "args": ["-c", "Add :CFBundleIconName string \(iconName)", "\(disguisedAppPath)/Contents/Info.plist"]]
                    ])
                } else {
                    lock.append([
                        "do":   ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconFile", "\(disguisedAppPath)/Contents/Info.plist"]],
                        "undo": ["command": "PlistBuddy", "args": ["-c", "Add :CFBundleIconFile string \(String(describing: iconName))", "\(disguisedAppPath)/Contents/Info.plist"]]
                    ])
                    lock.append([
                        "do":   ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconName", "\(disguisedAppPath)/Contents/Info.plist"]],
                        "undo": ["command": "PlistBuddy", "args": ["-c", "Add :CFBundleIconName string \(String(describing: iconName))", "\(disguisedAppPath)/Contents/Info.plist"]]
                    ])
                    lock.append([
                        "do":   ["command": "rm", "args": ["-rf", "\(disguisedAppPath)/Contents/Resources/AppIcon.icns"]],
                        "undo": ["command": "touch", "args": ["\(disguisedAppPath)/Contents/Resources/AppIcon.icns"]]
                    ])
                }

                lock.append([
                    "do":   ["command": "chflags", "args": ["uchg", hiddenApp]],
                    "undo": ["command": "chflags", "args": ["nouchg", hiddenApp]]
                ])
                lock.append([
                    "do":   ["command": "touch", "args": [disguisedAppPath]],
                    "undo": [:]
                ])
                lock.append([
                    "do":   ["command": "cp", "args": ["-Rf", disguisedAppPath, backupDir]]
                ])

                if sendToHelperBatch(lock) {
                    didChange = true
                    DispatchQueue.main.async{ [self] in
                        lockedApps[path] = LockedAppInfo(name: appName, execFile: execName)
                    }
                }
            }
        }

        // chỉ save 1 lần nếu có thay đổi
        if didChange {
            save()
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
            if success {
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
