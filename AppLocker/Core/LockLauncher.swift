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
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
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
            return InstalledApp(
                name: name,
                bundleID: bundleID,
                icon: icon,
                path: (fallbackLauncher ?? url).path
            )
        } else if let launcher = fallbackLauncher {
            let name = launcher.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: launcher.path)
            icon.size = NSSize(width: 32, height: 32)
            return InstalledApp(name: name, bundleID: "", icon: icon, path: launcher.path)
        }
        return nil
    }

    // MARK: - Persistence helper
    func save() {
        ConfigStore.shared.save(self.lockedApps)
    }

    // MARK: - Core toggle logic (paths are the paths passed from UI)
    func toggleLock(for paths: [String]) {
        var didChange = false
        let uid = getuid()
        let gid = getgid()

        for path in paths {
            if let lockedInfo = lockedApps[path] {
                if performUnlock(path: path, info: lockedInfo, uid: uid, gid: gid) {
                    didChange = true
                }
            } else {
                if performLock(path: path) {
                    didChange = true
                }
            }
        }

        if didChange { save() }
    }

    // MARK: - Private Actions
    private func performUnlock(
        path: String,
        info: LockedAppConfig,
        uid: uid_t,
        gid: gid_t) -> Bool {
        guard let ctx = AppPathContext(path: path) else { return false }
        let execFile = info.execFile ?? ""
        let execPath = "\(ctx.hiddenAppPath)/Contents/MacOS/\(execFile)"

        let unlockCommands: [[String: Any]] = [
            [
                "do": ["command": "chflags", "args": ["nouchg", ctx.hiddenAppPath]],
                "undo": ["command": "chflags", "args": ["uchg", ctx.hiddenAppPath]]
            ], [
                "do": ["command": "chflags", "args": ["nouchg", execPath]],
                "undo": ["command": "chflags", "args": ["uchg", execPath]]
            ], [
                "do": ["command": "chown", "args": ["\(uid):\(gid)", execPath]],
                "undo": ["command": "chown", "args": ["root:wheel", execPath]]
            ], [
                "do": ["command": "rm", "args": ["-rf", ctx.disguisedAppPath]],
                "undo": ["command": "cp", "args":
                            ["-Rf", "\(ctx.backupDir)/\(ctx.appName).app", ctx.baseDir]
                        ]
            ], [
                "do": ["command": "mv", "args": [ctx.hiddenAppPath, ctx.disguisedAppPath]],
                "undo": ["command": "mv", "args": [ctx.disguisedAppPath, ctx.hiddenAppPath]]
            ], [
                "do": ["command": "touch", "args": [ctx.disguisedAppPath]],
                "undo": [:]
            ], [
                "do": ["command": "chflags", "args": ["nohidden", ctx.disguisedAppPath]],
                "undo": ["command": "chflags", "args": ["hidden", ctx.disguisedAppPath]]
            ], [
                "do": ["command": "chmod", "args": [
                    "755", "\(ctx.disguisedAppPath)/Contents/MacOS/\(execFile)"]
                      ],
                "undo": ["command": "chmod", "args": [
                    "000", "\(ctx.disguisedAppPath)/Contents/MacOS/\(execFile)"]]
            ], [
                "do": ["command": "rm", "args": ["-rf", ctx.backupDir]]
            ]
        ]

        if sendToHelperBatch(unlockCommands) {
            DispatchQueue.main.async { self.lockedApps.removeValue(forKey: path) }
            return true
        }
        return false
    }

    private func performLock(path: String) -> Bool {
        let appURL = URL(fileURLWithPath: path)
        guard let infoPlist = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let execName = infoPlist["CFBundleExecutable"] as? String,
              let ctx = AppPathContext(path: path, execName: execName) else { return false }

        createBackupDirectory(at: ctx.backupDir)

        guard let sha = computeSHA(forPath: ctx.originalExecPath) else { return false }
        let launcherURL = Bundle.main.url(forResource: "Launcher", withExtension: "app")!

        var lockCommands: [[String: Any]] = [
            [
                "do": ["command": "cp", "args": ["-Rf", launcherURL.path, ctx.baseDir]],
                "undo": ["command": "rm", "args": ["-rf", "\(ctx.baseDir)/Launcher.app"]]
            ], [
                "do": ["command": "mkdir", "args": ["-p", ctx.launcherResources]],
                "undo": ["command": "rm", "args": ["-rf", ctx.launcherResources]]
            ], [
                "do": ["command": "mv", "args": [appURL.path, ctx.hiddenAppPath]],
                "undo": ["command": "mv", "args": [ctx.hiddenAppPath, appURL.path]]
            ], [
                "do": ["command": "chmod", "args": [
                    "000", "\(ctx.hiddenAppPath)/Contents/MacOS/\(execName)"]
                      ]
            ], [
                "do": ["command": "chown", "args": [
                    "root:wheel", "\(ctx.hiddenAppPath)/Contents/MacOS/\(execName)"]]
            ], [
                "do": ["command": "chflags", "args": ["hidden", ctx.hiddenAppPath]]
            ], [
                "do": ["command": "mv", "args": [
                    "\(ctx.baseDir)/Launcher.app", ctx.disguisedAppPath]]
            ], [
                "do": ["command": "chflags", "args": [
                    "uchg", "\(ctx.hiddenAppPath)/Contents/MacOS/\(execName)"]]
            ], [
                "do": ["command": "PlistBuddy", "args": [
                    "-c",
                    "Set :CFBundleIdentifier com.TranPhuong319.AppLocker.Launcher-\(ctx.appName)",
                    "\(ctx.disguisedAppPath)/Contents/Info.plist"]]
            ], [
                "do": ["command": "PlistBuddy", "args": [
                    "-c", "Set :CFBundleName \(ctx.appName)",
                    "\(ctx.disguisedAppPath)/Contents/Info.plist"]]
            ], [
                "do": ["command": "PlistBuddy", "args": [
                    "-c", "Set :CFBundleExecutable \(ctx.appName)",
                    "\(ctx.disguisedAppPath)/Contents/Info.plist"]]
            ], [
                "do": ["command": "mv", "args": [
                    "\(ctx.disguisedAppPath)/Contents/MacOS/Launcher",
                    "\(ctx.disguisedAppPath)/Contents/MacOS/\(ctx.appName)"]]
            ]
        ]

        appendIconCommands(to: &lockCommands, ctx: ctx, infoPlist: infoPlist)

        lockCommands.append(["do": ["command": "chflags", "args": ["uchg", ctx.hiddenAppPath]]])
        lockCommands.append(
            ["do": ["command": "cp", "args": ["-Rf", ctx.disguisedAppPath, ctx.backupDir]]]
        )

        if sendToHelperBatch(lockCommands) {
            updateLockedState(path: path, ctx: ctx, sha: sha, execName: execName)
            return true
        }
        return false
    }

    // MARK: - Sub-helpers
    private func createBackupDirectory(at path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private func updateLockedState(path: String,
                                   ctx: AppPathContext,
                                   sha: String,
                                   execName: String) {
        let bundleID = Bundle(url: ctx.appURL)?.bundleIdentifier ?? ""
        let mode = modeLock?.rawValue ?? AppMode.launcher.rawValue
        let cfg = LockedAppConfig(
            bundleID: bundleID,
            path: path,
            sha256: sha,
            blockMode: mode,
            execFile: execName,
            name: ctx.appName
        )
        DispatchQueue.main.async { self.lockedApps[path] = cfg }
    }

    private func appendIconCommands(
        to commands: inout [[String: Any]], ctx: AppPathContext, infoPlist: [String: Any]) {
        var iconName: String?
        if let icon = infoPlist["CFBundleIconFile"] as? String {
            iconName = icon.hasSuffix(".icns") ? String(icon.dropLast(5)) : icon
        }

        if let name = iconName {
            let sourceIcon = ctx.appURL.appendingPathComponent(
                "Contents/Resources/\(name).icns"
            ).path
            let destIcon = "\(ctx.baseDir)/Launcher.app/Contents/Resources/AppIcon.icns"

            commands.insert([
                "do": ["command": "cp", "args": [sourceIcon, destIcon]],
                "undo": ["command": "rm", "args": ["-f", destIcon]]
            ], at: 1)

            commands.append([
                "do": ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconName", "\(ctx.disguisedAppPath)/Contents/Info.plist"]],
                "undo": ["command": "PlistBuddy", "args": [
                    "-c", "Add :CFBundleIconName string \(name)",
                    "\(ctx.disguisedAppPath)/Contents/Info.plist"]]
            ])
        } else {
            appendFallbackIconCommands(to: &commands, ctx: ctx)
        }
    }

    private func appendFallbackIconCommands(
        to commands: inout [[String: Any]],
        ctx: AppPathContext) {
        let plistPath = "\(ctx.disguisedAppPath)/Contents/Info.plist"
        let iconPath = "\(ctx.disguisedAppPath)/Contents/Resources/AppIcon.icns"

        commands.append(contentsOf: [
            [
                "do": ["command": "PlistBuddy", "args": [
                    "-c", "Delete :CFBundleIconFile", plistPath]]
            ], [
                "do": ["command": "PlistBuddy", "args": [
                    "-c", "Delete :CFBundleIconName", plistPath]]
            ], [
                "do": ["command": "rm", "args": ["-rf", iconPath]],
                "undo": ["command": "touch", "args": [iconPath]]
            ]
        ])
    }

    // helper to send work to privileged helper via XPC (unchanged)
    func sendToHelperBatch(_ commandList: [[String: Any]]) -> Bool {
        let conn = NSXPCConnection(
            machServiceName: "com.TranPhuong319.AppLocker.Helper",
            options: .privileged
        )
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

// MARK: - Path Helper
private struct AppPathContext {
    let appURL: URL
    let appName: String
    let baseDir: String
    let disguisedAppPath: String
    let hiddenAppPath: String
    let launcherResources: String
    let backupDir: String
    let markerApp: String
    let originalExecPath: String

    init?(path: String, execName: String? = nil) {
        let url = URL(fileURLWithPath: path)
        self.appURL = url
        self.appName = url.deletingPathExtension().lastPathComponent
        self.baseDir = url.deletingLastPathComponent().path
        self.disguisedAppPath = "\(baseDir)/\(appName).app"
        self.hiddenAppPath = "\(baseDir)/.\(appName).app"
        self.launcherResources = "\(baseDir)/Launcher.app/Contents/Resources/Locked"
        self.markerApp = "\(disguisedAppPath)/Contents/Resources/\(appName).app"

        self.backupDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AppLocker/Backups/\(appName)")
            .path

        if let exec = execName {
            self.originalExecPath = url.appendingPathComponent("Contents/MacOS/\(exec)").path
        } else {
            self.originalExecPath = ""
        }
    }
}
