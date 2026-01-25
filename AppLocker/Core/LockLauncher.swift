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
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
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
    }

    // MARK: - Installed apps discovery (Removed in favor of Spotlight)

    // MARK: - Persistence helper
    func save() {
        ConfigStore.shared.save(self.lockedApps)
    }

    // MARK: - Core toggle logic (paths are the paths passed from UI)
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
    private func performUnlock(
        path: String,
        info: LockedAppConfig,
        uid: uid_t,
        gid: gid_t
    ) -> Bool {
        guard let pathContext = AppPathContext(path: path) else { return false }
        let executableFileName = info.execFile ?? ""
        let execPath = "\(pathContext.hiddenAppPath)/Contents/MacOS/\(executableFileName)"

        let helperUnlockCommands: [[String: Any]] = [
            [
                "do": ["command": "chflags", "args": ["nouchg", pathContext.hiddenAppPath]],
                "undo": ["command": "chflags", "args": ["uchg", pathContext.hiddenAppPath]]
            ],
            [
                "do": ["command": "chflags", "args": ["nouchg", execPath]],
                "undo": ["command": "chflags", "args": ["uchg", execPath]]
            ],
            [
                "do": ["command": "chown", "args": ["\(uid):\(gid)", execPath]],
                "undo": ["command": "chown", "args": ["root:wheel", execPath]]
            ],
            [
                "do": ["command": "rm", "args": ["-rf", pathContext.disguisedAppPath]],
                "undo": [
                    "command": "cp",
                    "args":
                        ["-Rf", "\(pathContext.backupDir)/\(pathContext.appName).app", pathContext.baseDir]
                ]
            ],
            [
                "do": ["command": "mv", "args": [pathContext.hiddenAppPath, pathContext.disguisedAppPath]],
                "undo": ["command": "mv", "args": [pathContext.disguisedAppPath, pathContext.hiddenAppPath]]
            ],
            [
                "do": ["command": "touch", "args": [pathContext.disguisedAppPath]],
                "undo": [:]
            ],
            [
                "do": ["command": "chflags", "args": ["nohidden", pathContext.disguisedAppPath]],
                "undo": ["command": "chflags", "args": ["hidden", pathContext.disguisedAppPath]]
            ],
            [
                "do": [
                    "command": "chmod",
                    "args": [
                        "755", "\(pathContext.disguisedAppPath)/Contents/MacOS/\(executableFileName)"
                    ]
                ],
                "undo": [
                    "command": "chmod",
                    "args": [
                        "000", "\(pathContext.disguisedAppPath)/Contents/MacOS/\(executableFileName)"
                    ]
                ]
            ],
            [
                "do": ["command": "rm", "args": ["-rf", pathContext.backupDir]]
            ]
        ]

        if sendToHelperBatch(helperUnlockCommands) {
            DispatchQueue.main.async { self.lockedApps.removeValue(forKey: path) }
            return true
        }
        return false
    }

    private func performLock(path: String) -> Bool {
        let appURL = URL(fileURLWithPath: path)
        guard let bundle = Bundle(url: appURL) else { return false }
        
        let infoPlist = (bundle.infoDictionary ?? [:]) as [String: Any]
        
        // Robust Executable Resolution
        var resolvedExecPath = bundle.executablePath
        if resolvedExecPath == nil {
            let appName = appURL.deletingPathExtension().lastPathComponent
            let potentialPath = appURL.appendingPathComponent("Contents/MacOS/\(appName)").path
            if FileManager.default.fileExists(atPath: potentialPath) {
                resolvedExecPath = potentialPath
            }
        }
        
        guard let finalExecPath = resolvedExecPath else {
            Logfile.core.error("Cannot resolve executable path for \(path)")
            return false
        }
        
        let execName = URL(fileURLWithPath: finalExecPath).lastPathComponent
        
        guard let pathContext = AppPathContext(path: path, execName: execName) else { return false }

        createBackupDirectory(at: pathContext.backupDir)

        guard let sha = computeSHA(forPath: pathContext.originalExecPath) else { return false }
        let launcherURL = Bundle.main.url(forResource: "Launcher", withExtension: "app")!

        var helperLockCommands: [[String: Any]] = [
            [
                "do": ["command": "cp", "args": ["-Rf", launcherURL.path, pathContext.baseDir]],
                "undo": ["command": "rm", "args": ["-rf", "\(pathContext.baseDir)/Launcher.app"]]
            ],
            [
                "do": ["command": "mkdir", "args": ["-p", pathContext.launcherResources]],
                "undo": ["command": "rm", "args": ["-rf", pathContext.launcherResources]]
            ],
            [
                "do": ["command": "mv", "args": [appURL.path, pathContext.hiddenAppPath]],
                "undo": ["command": "mv", "args": [pathContext.hiddenAppPath, appURL.path]]
            ],
            [
                "do": [
                    "command": "chmod",
                    "args": [
                        "000", "\(pathContext.hiddenAppPath)/Contents/MacOS/\(execName)"
                    ]
                ]
            ],
            [
                "do": [
                    "command": "chown",
                    "args": [
                        "root:wheel", "\(pathContext.hiddenAppPath)/Contents/MacOS/\(execName)"
                    ]
                ]
            ],
            [
                "do": ["command": "chflags", "args": ["hidden", pathContext.hiddenAppPath]]
            ],
            [
                "do": [
                    "command": "mv",
                    "args": [
                        "\(pathContext.baseDir)/Launcher.app", pathContext.disguisedAppPath
                    ]
                ]
            ],
            [
                "do": [
                    "command": "chflags",
                    "args": [
                        "uchg", "\(pathContext.hiddenAppPath)/Contents/MacOS/\(execName)"
                    ]
                ]
            ],
            [
                "do": [
                    "command": "PlistBuddy",
                    "args": [
                        "-c",
                        "Set :CFBundleIdentifier com.TranPhuong319.AppLocker.Launcher-\(pathContext.appName)",
                        "\(pathContext.disguisedAppPath)/Contents/Info.plist"
                    ]
                ]
            ],
            [
                "do": [
                    "command": "PlistBuddy",
                    "args": [
                        "-c", "Set :CFBundleName \(pathContext.appName)",
                        "\(pathContext.disguisedAppPath)/Contents/Info.plist"
                    ]
                ]
            ],
            [
                "do": [
                    "command": "PlistBuddy",
                    "args": [
                        "-c", "Set :CFBundleExecutable \(pathContext.appName)",
                        "\(pathContext.disguisedAppPath)/Contents/Info.plist"
                    ]
                ]
            ],
            [
                "do": [
                    "command": "mv",
                    "args": [
                        "\(pathContext.disguisedAppPath)/Contents/MacOS/Launcher",
                        "\(pathContext.disguisedAppPath)/Contents/MacOS/\(pathContext.appName)"
                    ]
                ]
            ]
        ]

        appendIconCommands(to: &helperLockCommands, pathContext: pathContext, infoPlist: infoPlist)

        helperLockCommands.append(["do": ["command": "chflags", "args": ["uchg", pathContext.hiddenAppPath]]])
        helperLockCommands.append(
            ["do": ["command": "cp", "args": ["-Rf", pathContext.disguisedAppPath, pathContext.backupDir]]]
        )

        if sendToHelperBatch(helperLockCommands) {
            updateLockedState(path: path, pathContext: pathContext, sha: sha, execName: execName)
            return true
        }
        return false
    }

    // MARK: - Sub-helpers
    private func createBackupDirectory(at path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private func updateLockedState(
        path: String,
        pathContext: AppPathContext,
        sha: String,
        execName: String
    ) {
        let bundleID = Bundle(url: pathContext.appURL)?.bundleIdentifier ?? ""
        let mode = modeLock?.rawValue ?? AppMode.launcher.rawValue
        let appConfig = LockedAppConfig(
            bundleID: bundleID,
            path: path,
            sha256: sha,
            blockMode: mode,
            execFile: execName,
            name: pathContext.appName
        )
        DispatchQueue.main.async { self.lockedApps[path] = appConfig }
    }

    private func appendIconCommands(
        to commands: inout [[String: Any]], pathContext: AppPathContext, infoPlist: [String: Any]
    ) {
        var iconName: String?
        if let icon = infoPlist["CFBundleIconFile"] as? String {
            iconName = icon.hasSuffix(".icns") ? String(icon.dropLast(5)) : icon
        }

        if let name = iconName {
            let sourceIcon = pathContext.appURL.appendingPathComponent(
                "Contents/Resources/\(name).icns"
            ).path
            let destIcon = "\(pathContext.baseDir)/Launcher.app/Contents/Resources/AppIcon.icns"

            commands.insert(
                [
                    "do": ["command": "cp", "args": [sourceIcon, destIcon]],
                    "undo": ["command": "rm", "args": ["f", destIcon]]
                ], at: 1)

            commands.append([
                "do": [
                    "command": "PlistBuddy",
                    "args": [
                        "-c", "Delete :CFBundleIconName",
                        "\(pathContext.disguisedAppPath)/Contents/Info.plist"
                    ]
                ],
                "undo": [
                    "command": "PlistBuddy",
                    "args": [
                        "-c", "Add :CFBundleIconName string \(name)",
                        "\(pathContext.disguisedAppPath)/Contents/Info.plist"
                    ]
                ]
            ])
        } else {
            appendFallbackIconCommands(to: &commands, pathContext: pathContext)
        }
    }

    private func appendFallbackIconCommands(
        to commands: inout [[String: Any]],
        pathContext: AppPathContext
    ) {
        let plistPath = "\(pathContext.disguisedAppPath)/Contents/Info.plist"
        let iconPath = "\(pathContext.disguisedAppPath)/Contents/Resources/AppIcon.icns"

        commands.append(contentsOf: [
            [
                "do": [
                    "command": "PlistBuddy",
                    "args": [
                        "-c", "Delete :CFBundleIconFile", plistPath
                    ]
                ]
            ],
            [
                "do": [
                    "command": "PlistBuddy",
                    "args": [
                        "-c", "Delete :CFBundleIconName", plistPath
                    ]
                ]
            ],
            [
                "do": ["command": "rm", "args": ["-rf", iconPath]],
                "undo": ["command": "touch", "args": [iconPath]]
            ]
        ])
    }

    // helper to send work to privileged helper via XPC (authenticated)
    func sendToHelperBatch(_ commandList: [[String: Any]]) -> Bool {
        let xpcConnection = NSXPCConnection(
            machServiceName: "com.TranPhuong319.AppLocker.Helper",
            options: .privileged
        )
        xpcConnection.remoteObjectInterface = NSXPCInterface(with: AppLockerHelperProtocol.self)
        xpcConnection.resume()

        let semaphore = DispatchSemaphore(value: 0)
        var result: Bool = false

        let proxy =
            xpcConnection.remoteObjectProxyWithErrorHandler { error in
                Logfile.core.pError("XPC error: \(error)")
                result = false
                semaphore.signal()
            } as? AppLockerHelperProtocol

        // ---------------------------------------------------------
        // AUTH Handshake before sending commands
        // ---------------------------------------------------------
        func doAuth(completion: @escaping (Bool) -> Void) {
            let appPublicKeyTag = KeychainHelper.Keys.appPublic

            // 1. Ensure Client Keys
            if !KeychainHelper.shared.hasKey(tag: appPublicKeyTag) {
                try? KeychainHelper.shared.generateKeys(tag: appPublicKeyTag)
            }

            // 2. Prepare Auth Data
            let clientNonce = Data.random(count: 32)
            guard let clientSig = KeychainHelper.shared.sign(data: clientNonce, tag: appPublicKeyTag),
                let pubKeyData = KeychainHelper.shared.exportPublicKey(tag: appPublicKeyTag)
            else {
                Logfile.core.error("Helper Auth: Failed to sign/export client data")
                completion(false)
                return
            }

            proxy?.authenticate(
                clientNonce: clientNonce, clientSig: clientSig, clientPublicKey: pubKeyData
            ) { serverNonce, serverSig, serverPubKey, success in
                guard success, let sNonce = serverNonce, let sSig = serverSig,
                    let sKeyData = serverPubKey
                else {
                    Logfile.core.error("Helper Auth: Server rejected or invalid response")
                    completion(false)
                    return
                }

                // 3. Verify Server (Curve25519)
                let combined = clientNonce + sNonce

                if KeychainHelper.shared.verify(
                    signature: sSig, originalData: combined, publicKeyData: sKeyData) {
                    Logfile.core.log("Helper Auth: Success")
                    completion(true)
                } else {
                    Logfile.core.error("Helper Auth: Server signature verification failed")
                    completion(false)
                }
            }
        }

        // Execute Auth then Batch
        doAuth { authSuccess in
            if authSuccess {
                proxy?.sendBatch(commandList) { success, message in
                    if success {
                        Logfile.core.pInfo("Success: \(message)")
                    } else {
                        Logfile.core.pError("Failure: \(message)")
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

    func reloadAllApps() {
        // Spotlight updates automatically, or manually re-start query if needed
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
