//
//  LockLauncher.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import AppKit
import CryptoKit
import Foundation

class LockLauncher: LockManagerProtocol {
    @Published var lockedApps: [String: LockedAppConfig] = [:]  // keyed by path
    @Published var allApps: [InstalledApp] = []

    private var currentBundleFile: URL {
        Bundle.main.bundleURL
    }

    init() {
        self.lockedApps = ConfigStore.shared.load()
    }

    // MARK: - Persistence helper
    func save() {
        ConfigStore.shared.save(self.lockedApps)
    }

    // MARK: - Core toggle logic
    func toggleLock(for paths: [String]) {
        var hasConfigChanged = false
        let userUID = getuid()
        let groupGID = getgid()

        for path in paths {
            if let lockedAppConfig = lockedApps[path] {
                if performUnlock(path: path, info: lockedAppConfig, uid: userUID, gid: groupGID) {
                    hasConfigChanged = true
                }
            } else {
                if performLock(path: path) {
                    hasConfigChanged = true
                }
            }
        }

        if hasConfigChanged { save() }
    }

    // MARK: - Private Actions
    private func performUnlock(path: String, info: LockedAppConfig, uid: uid_t, gid: gid_t) -> Bool {
        guard let context = AppPathContext(path: path) else { return false }
        
        let commands: [[String: Any]] = [
            chflagsCmd(context.hiddenAppPath, flags: "nouchg", undo: "uchg"),
            chflagsCmd(path, flags: "nouchg", undo: "uchg"),
            moveCmd(from: context.hiddenAppPath, targetPath: context.disguisedAppPath),
            chflagsCmd(context.disguisedAppPath, flags: "nohidden", undo: "hidden"),
            ["do": ["command": "touch", "args": [context.disguisedAppPath]]],
            ["do": ["command": "rm", "args": ["-rf", context.backupDir]]]
        ]

        if sendToHelperBatch(commands) {
            DispatchQueue.main.async { self.lockedApps.removeValue(forKey: path) }
            return true
        }
        return false
    }

    private func performLock(path: String) -> Bool {
        let appURL = URL(fileURLWithPath: path)
        guard let bundle = Bundle(url: appURL) else { return false }
        let infoPlist = (bundle.infoDictionary ?? [:]) as [String: Any]
        
        guard let execName = infoPlist["CFBundleExecutable"] as? String,
              let context = AppPathContext(path: path, execName: execName) else { return false }

        createBackupDirectory(at: context.backupDir)

        guard let sha = computeSHA(forPath: context.originalExecPath),
              let launcherURL = Bundle.main.url(forResource: "Launcher", withExtension: "app") else { return false }

        var commands: [[String: Any]] = [
            ["do": ["command": "cp", "args": ["-Rf", launcherURL.path, context.baseDir]]],
            chflagsCmd(context.disguisedAppPath, flags: "nouchg", undo: "uchg"),
            ["do": ["command": "mv", "args": [context.disguisedAppPath, context.hiddenAppPath]]],
            chflagsCmd(context.hiddenAppPath, flags: "hidden", undo: "nohidden"),
            ["do": ["command": "mv", "args": ["\(context.baseDir)/Launcher.app", context.disguisedAppPath]]],
            ["do": ["command": "mv", "args": [
                "\(context.disguisedAppPath)/Contents/MacOS/Launcher",
                "\(context.disguisedAppPath)/Contents/MacOS/\(context.appName)"
            ]]],
            chflagsCmd("\(context.hiddenAppPath)/Contents/MacOS/\(execName)", flags: "uchg", undo: "nouchg")
        ]

        appendIconCommands(to: &commands, context: context, infoPlist: infoPlist)
        commands.append(chflagsCmd(context.hiddenAppPath, flags: "uchg", undo: "nouchg"))

        if sendToHelperBatch(commands) {
            updateLockedState(path: path, context: context, sha: sha, execName: execName)
            return true
        }
        return false
    }

    // MARK: - Command Builders
    private func chflagsCmd(_ path: String, flags: String, undo: String? = nil) -> [String: Any] {
        var cmd: [String: Any] = ["do": ["command": "chflags", "args": [flags, path]]]
        if let undo = undo {
            cmd["undo"] = ["command": "chflags", "args": [undo, path]]
        }
        return cmd
    }

    private func moveCmd(from: String, targetPath: String) -> [String: Any] {
        return [
            "do": ["command": "mv", "args": [from, targetPath]],
            "undo": ["command": "mv", "args": [targetPath, from]]
        ]
    }

    // MARK: - Sub-helpers
    private func createBackupDirectory(at path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private func updateLockedState(path: String, context: AppPathContext, sha: String, execName: String) {
        let bundleID = Bundle(url: context.appURL)?.bundleIdentifier ?? ""
        let mode = modeLock?.rawValue ?? "Launcher"
        let appConfig = LockedAppConfig(
            bundleID: bundleID,
            path: path,
            sha256: sha,
            blockMode: mode,
            execFile: execName,
            name: context.appName
        )
        DispatchQueue.main.async { self.lockedApps[path] = appConfig }
    }

    // MARK: - Icon Management
    private func appendIconCommands(to commands: inout [[String: Any]], context: AppPathContext, infoPlist: [String: Any]) {
        var iconName: String?
        if let icon = infoPlist["CFBundleIconFile"] as? String {
            iconName = icon.hasSuffix(".icns") ? String(icon.dropLast(5)) : icon
        }

        if let name = iconName {
            let plistPath = "\(context.disguisedAppPath)/Contents/Info.plist"
            commands.append(contentsOf: [
                ["do": ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleIconFile \(name)", plistPath]]],
                ["do": ["command": "PlistBuddy", "args": ["-c", "Set :CFBundleIconName \(name)", plistPath]]]
            ])
        } else {
            appendFallbackIconCommands(to: &commands, context: context)
        }
    }

    private func appendFallbackIconCommands(to commands: inout [[String: Any]], context: AppPathContext) {
        let plistPath = "\(context.disguisedAppPath)/Contents/Info.plist"
        let iconPath = "\(context.disguisedAppPath)/Contents/Resources/AppIcon.icns"

        commands.append(contentsOf: [
            ["do": ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconFile", plistPath]]],
            ["do": ["command": "PlistBuddy", "args": ["-c", "Delete :CFBundleIconName", plistPath]]],
            ["do": ["command": "rm", "args": ["-rf", iconPath]], "undo": ["command": "touch", "args": [iconPath]]]
        ])
    }

    // MARK: - XPC & Auth logic
    func sendToHelperBatch(_ commandList: [[String: Any]]) -> Bool {
        let xpcConnection = NSXPCConnection(machServiceName: "com.TranPhuong319.AppLocker.Helper", options: .privileged)
        xpcConnection.remoteObjectInterface = NSXPCInterface(with: AppLockerHelperProtocol.self)
        xpcConnection.resume()

        let semaphore = DispatchSemaphore(value: 0)
        var result: Bool = false

        let proxy = xpcConnection.remoteObjectProxyWithErrorHandler { error in
            Logfile.core.error("XPC error: \(error)")
            result = false
            semaphore.signal()
        } as? AppLockerHelperProtocol

        performXPCAuth(with: proxy) { authSuccess in
            if authSuccess {
                proxy?.sendBatch(commandList) { success, message in
                    if success { Logfile.core.info("Success: \(message)") } else {
                        Logfile.core.error("Failure: \(message)")
                    }
                    result = success
                    semaphore.signal()
                }
            } else {
                result = false
                semaphore.signal()
            }
        }

        semaphore.wait()
        xpcConnection.invalidate()
        return result
    }

    private func performXPCAuth(with proxy: AppLockerHelperProtocol?, completion: @escaping (Bool) -> Void) {
        let appPublicKeyTag = KeychainHelper.Keys.appPublic

        // 1. Ensure Client Keys
        if !KeychainHelper.shared.hasKey(tag: appPublicKeyTag) {
            try? KeychainHelper.shared.generateKeys(tag: appPublicKeyTag)
        }

        // 2. Prepare Auth Data
        let clientNonce = Data.random(count: 32)
        guard let clientSig = KeychainHelper.shared.sign(data: clientNonce, tag: appPublicKeyTag),
              let pubKeyData = KeychainHelper.shared.exportPublicKey(tag: appPublicKeyTag) else {
            Logfile.core.error("Helper Auth: Failed to sign/export client data")
            completion(false)
            return
        }

        proxy?.authenticate(clientNonce: clientNonce, clientSig: clientSig, clientPublicKey: pubKeyData) { serverNonce, serverSig, serverPubKey, success in
            guard success, let sNonce = serverNonce, let sSig = serverSig, let sKeyData = serverPubKey else {
                Logfile.core.error("Helper Auth: Server rejected or invalid response")
                completion(false)
                return
            }

            // 3. Verify Server (Curve25519)
            let combined = clientNonce + sNonce
            if KeychainHelper.shared.verify(signature: sSig, originalData: combined, publicKeyData: sKeyData) {
                Logfile.core.log("Helper Auth: Success")
                completion(true)
            } else {
                Logfile.core.error("Helper Auth: Server signature verification failed")
                completion(false)
            }
        }
    }

    func reloadAllApps() {}
    func isLocked(path: String) -> Bool { lockedApps[path] != nil }
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

        self.backupDir =
            FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AppLocker/Backups/\(appName)")
            .path

        if let exec = execName {
            self.originalExecPath = url.appendingPathComponent("Contents/MacOS/\(exec)").path
        } else {
            self.originalExecPath = ""
        }
    }
}
