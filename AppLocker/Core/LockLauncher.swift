//
//  LockLauncher.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import AppKit
import Foundation
import CryptoKit

class LockLauncher: LockManagerProtocol {
    @Published var lockedApps: [String: LockedAppConfig] = [:] // keyed by path
    @Published var allApps: [InstalledApp] = []

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
        // load persisted config into dictionary
        self.lockedApps = ConfigStore.shared.load()
        self.allApps = getInstalledApps()
    }

    // MARK: - Installed apps discovery (unchanged)
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

    // MARK: - Persistence helper
    func save() {
        ConfigStore.shared.save(self.lockedApps)
    }

    // MARK: - SHA helper
    private func computeSHA(for executablePath: String) -> String {
        let url = URL(fileURLWithPath: executablePath)
        guard let data = try? Data(contentsOf: url) else { return "" }
        let h = SHA256.hash(data: data)
        return h.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Core toggle logic (paths are the paths passed from UI)
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
            } catch {
                NSLog("Failed create backup dir: \(error.localizedDescription)")
            }

            // If currently locked -> unlock
            if let lockedInfo = lockedApps[path] {
                let execFile = lockedInfo.execFile ?? ""
                let execPath = "\(hiddenApp)/Contents/MacOS/\(execFile)"

                let unlock: [[String: Any]] = [
                    ["do": ["command": "chflags", "args": ["nouchg", hiddenApp]],
                     "undo": ["command": "chflags", "args": ["uchg", hiddenApp]]],
                    ["do": ["command": "chflags", "args": ["nouchg", execPath]],
                     "undo": ["command": "chflags", "args": ["uchg", execPath]]],
                    ["do": ["command": "chown", "args": ["\(uid):\(gid)", execPath]],
                     "undo": ["command": "chown", "args": ["root:wheel", execPath]]],
                    ["do": ["command": "rm", "args": ["-rf", disguisedAppPath]],
                     "undo": ["command": "cp", "args": ["-Rf", "\(backupDir)/\(appName).app", baseDir]]],
                    ["do": ["command": "mv", "args": [hiddenApp, disguisedAppPath]],
                     "undo": ["command": "mv", "args": [disguisedAppPath, hiddenApp]]],
                    ["do": ["command": "touch", "args": [disguisedAppPath]], "undo": [:]],
                    ["do": ["command": "chflags", "args": ["nohidden", disguisedAppPath]],
                     "undo": ["command": "chflags", "args": ["hidden", disguisedAppPath]]],
                    ["do": ["command": "chmod", "args": ["755", "\(disguisedAppPath)/Contents/MacOS/\(execFile)"]],
                     "undo": ["command": "chmod", "args": ["000", "\(disguisedAppPath)/Contents/MacOS/\(execFile)"]]],
                    ["do": ["command": "touch", "args": [disguisedAppPath]], "undo": [:]],
                    ["do": ["command": "rm", "args": ["-rf", backupDir]]]
                ]

                if sendToHelperBatch(unlock) {
                    didChange = true
                    DispatchQueue.main.async {
                        self.lockedApps.removeValue(forKey: path)
                    }
                }

            } else {
                // -> Lock
                guard let infoPlist = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                      let execName = infoPlist["CFBundleExecutable"] as? String else {
                    NSLog("Cannot read Info.plist for \(path)")
                    continue
                }

                var iconName: String?
                if let icon = infoPlist["CFBundleIconFile"] as? String {
                    iconName = icon.hasSuffix(".icns") ? String(icon.dropLast(5)) : icon
                }

                let launcherURL = Bundle.main.url(forResource: "Launcher", withExtension: "app")!

                // compute SHA from original executable before we move/lock it
                let originalExecPath = appURL.appendingPathComponent("Contents/MacOS/\(execName)").path
                let sha = computeSHA(for: originalExecPath)

                var lock: [[String: Any]] = [
                    ["do": ["command": "cp", "args": ["-Rf", launcherURL.path, baseDir]],
                     "undo": ["command": "rm", "args": ["-rf", "\(baseDir)/Launcher.app"]]],
                    ["do": ["command": "mkdir", "args": ["-p", launcherResources]],
                     "undo": ["command": "rm", "args": ["-rf", launcherResources]]],
                    ["do": ["command": "mv", "args": [appURL.path, hiddenApp]],
                     "undo": ["command": "mv", "args": [hiddenApp, appURL.path]]],
                    ["do": ["command": "chmod", "args": ["000", "\(hiddenApp)/Contents/MacOS/\(execName)"]],
                     "undo": ["command": "chmod", "args": ["755", "\(hiddenApp)/Contents/MacOS/\(execName)"]]],
                    ["do": ["command": "chown", "args": ["root:wheel", "\(hiddenApp)/Contents/MacOS/\(execName)"]],
                     "undo": ["command": "chown", "args": ["\(NSUserName()):staff", "\(hiddenApp)/Contents/MacOS/\(execName)"]]],
                    ["do": ["command": "chflags", "args": ["hidden", hiddenApp]],
                     "undo": ["command": "chflags", "args": ["nohidden", hiddenApp]]],
                    ["do": ["command": "mv", "args": ["\(baseDir)/Launcher.app", disguisedAppPath]],
                     "undo": ["command": "mv", "args": [disguisedAppPath, "\(baseDir)/Launcher.app"]]],
                    ["do": ["command": "chflags", "args": ["uchg", "\(hiddenApp)/Contents/MacOS/\(execName)"]],
                     "undo": ["command": "chflags", "args": ["nouchg", "\(hiddenApp)/Contents/MacOS/\(execName)"]]],
                    ["do": ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleIdentifier com.TranPhuong319.AppLocker.Launcher-\(appName)", "\(disguisedAppPath)/Contents/Info.plist"]],
                     "undo": ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIdentifier", "\(disguisedAppPath)/Contents/Info.plist"]]],
                    ["do": ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleName \(appName)", "\(disguisedAppPath)/Contents/Info.plist"]],
                     "undo": ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleName", "\(disguisedAppPath)/Contents/Info.plist"]]],
                    ["do": ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleExecutable \(appName)", "\(disguisedAppPath)/Contents/Info.plist"]],
                     "undo": ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleExecutable Launcher", "\(disguisedAppPath)/Contents/Info.plist"]]],
                    ["do": ["command": "mv", "args": ["\(disguisedAppPath)/Contents/MacOS/Launcher", "\(disguisedAppPath)/Contents/MacOS/\(appName)"]],
                     "undo": ["command": "mv", "args": ["\(disguisedAppPath)/Contents/MacOS/\(appName)", "\(disguisedAppPath)/Contents/MacOS/Launcher"]]],
                    ["do": ["command": "touch", "args": [launcherURL.path]],
                     "undo": ["command": "rm", "args": ["-rf", "\(baseDir)/Launcher.app"]]],
                    ["do": ["command": "touch", "args": [markerApp]], "undo": [:]]
                ]

                if let iconName = iconName {
                    lock.insert([
                        "do": ["command": "cp",
                               "args": [appURL.appendingPathComponent("Contents/Resources/\(iconName).icns").path,
                                        "\(baseDir)/Launcher.app/Contents/Resources/AppIcon.icns"]],
                        "undo": ["command": "rm", "args": ["-f", "\(baseDir)/Launcher.app/Contents/Resources/AppIcon.icns"]]
                    ], at: 1)
                    lock.append([
                        "do": ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconName", "\(disguisedAppPath)/Contents/Info.plist"]],
                        "undo": ["command": "PlistBuddy", "args": ["-c", "Add :CFBundleIconName string \(iconName)", "\(disguisedAppPath)/Contents/Info.plist"]]
                    ])
                } else {
                    lock.append([
                        "do": ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconFile", "\(disguisedAppPath)/Contents/Info.plist"]],
                        "undo": ["command": "PlistBuddy", "args": ["-c", "Add :CFBundleIconFile string \(String(describing: iconName))", "\(disguisedAppPath)/Contents/Info.plist"]]
                    ])
                    lock.append([
                        "do": ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconName", "\(disguisedAppPath)/Contents/Info.plist"]],
                        "undo": ["command": "PlistBuddy", "args": ["-c", "Add :CFBundleIconName string \(String(describing: iconName))", "\(disguisedAppPath)/Contents/Info.plist"]]
                    ])
                    lock.append([
                        "do": ["command": "rm", "args": ["-rf", "\(disguisedAppPath)/Contents/Resources/AppIcon.icns"]],
                        "undo": ["command": "touch", "args": ["\(disguisedAppPath)/Contents/Resources/AppIcon.icns"]]
                    ])
                }

                lock.append(["do": ["command": "chflags", "args": ["uchg", hiddenApp]],
                             "undo": ["command": "chflags", "args": ["nouchg", hiddenApp]]])
                lock.append(["do": ["command": "touch", "args": [disguisedAppPath]], "undo": [:]])
                lock.append(["do": ["command": "cp", "args": ["-Rf", disguisedAppPath, backupDir]]])

                if sendToHelperBatch(lock) {
                    didChange = true
                    DispatchQueue.main.async {
                        // save metadata (keyed by original path)
                        let bundleID = Bundle(url: appURL)?.bundleIdentifier ?? ""
                        let mode = modeLock?.rawValue ?? AppMode.launcher.rawValue
                        let cfg = LockedAppConfig(bundleID: bundleID,
                                                  path: path,
                                                  sha256: sha,
                                                  blockMode: mode,
                                                  execFile: execName,
                                                  name: appName)
                        self.lockedApps[path] = cfg
                    }
                }
            }
        }

        if didChange {
            save()
        }
    }

    // helper to send work to privileged helper via XPC (unchanged)
    func sendToHelperBatch(_ commandList: [[String: Any]]) -> Bool {
        let conn = NSXPCConnection(machServiceName: "com.TranPhuong319.AppLocker.Helper", options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: AppLockerHelperProtocol.self)
        conn.resume()

        let semaphore = DispatchSemaphore(value: 0)
        var result: Bool = false

        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            Logfile.core.error("XPC error: \(error, privacy: .public)")
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
