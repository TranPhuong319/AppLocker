//
//  Launcher.swift
//  Launcher
//
//  Created by Doe Phương on 24/07/2025.
//

import AppKit
import Foundation
import ServiceManagement

struct LockedAppInfo: Codable {
    let name: String
    let execFile: String

    enum CodingKeys: String, CodingKey {
        case name, execFile
    }
}

class Launcher {
    static let shared = Launcher()
    var pendingOpenFileURLs: [URL] = []

    func run() {
        Logfile.launcher.info("Launcher started")
        Logfile.launcher.info("CommandLine args: \(CommandLine.arguments)")

        let resourcesURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        guard checkResourcesFolder(resourcesURL) else { exit(1) }

        let lockedApps = loadLockedAppInfos()

        do {
            let appURLs = try FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "app" }

            for appURL in appURLs {
                handleApp(appURL, lockedApps: lockedApps)
                return // Only handle one app per launcher run.
            }

            Logfile.launcher.error("Can't find the App locked in the Resources")
            exit(1)

        } catch {
            Logfile.launcher.error("Error when approving the Resources folder: \(error)")
            exit(1)
        }
    }
}

// MARK: - Core Logic & Helpers
extension Launcher {
    private func checkResourcesFolder(_ url: URL) -> Bool {
        if !FileManager.default.fileExists(atPath: url.path) {
            Logfile.launcher.error("Folder not found: \(url.path)")
            return false
        }
        return true
    }

    private func handleApp(_ appURL: URL, lockedApps: [String: LockedAppInfo]) {
        let appName = appURL.deletingPathExtension().lastPathComponent

        guard let (launcherPath, lockedInfo) = lockedApps.first(where: { _, info in
            info.name == appName
        }) else {
            Logfile.launcher.warning("Can't find info for: \(appName)")
            exit(1)
        }

        let disguisedAppURL = URL(fileURLWithPath: launcherPath)
        let hiddenAppRealURL = disguisedAppURL.deletingLastPathComponent()
            .appendingPathComponent(".\(appName).app")

        let execPath = hiddenAppRealURL
            .appendingPathComponent("Contents/MacOS/\(lockedInfo.execFile)").path

        let unlockCmds = buildUnlockCommands(hiddenAppRealURL: hiddenAppRealURL, execPath: execPath)
        let lockCmds = buildLockCommands(hiddenAppRealURL: hiddenAppRealURL, execPath: execPath)

        authenticateAndOpenApp(
            lockedInfo: lockedInfo,
            hiddenAppRealURL: hiddenAppRealURL,
            execPath: execPath,
            unlockCmds: unlockCmds,
            lockCmds: lockCmds
        )
    }

    private func buildUnlockCommands(hiddenAppRealURL: URL, execPath: String) -> [[String: Any]] {
        let uid = getuid()
        let gid = getgid()
        return [
            [
                "do": ["command": "chflags", "args": ["nouchg", hiddenAppRealURL.path]],
                "undo": ["command": "chflags", "args": ["uchg", hiddenAppRealURL.path]]
            ],
            [
                "do": ["command": "chflags", "args": ["nouchg", execPath]],
                "undo": ["command": "chflags", "args": ["uchg", execPath]]
            ],
            [
                "do": ["command": "chmod", "args": ["a=rx", execPath]],
                "undo": ["command": "chmod", "args": ["000", execPath]]
            ],
            [
                "do": ["command": "chown", "args": ["\(uid):\(gid)", execPath]],
                "undo": ["command": "chown", "args": ["root:wheel", execPath]]
            ]
        ]
    }

    private func buildLockCommands(hiddenAppRealURL: URL, execPath: String) -> [[String: Any]] {
        return [
            [
                "do": ["command": "chmod", "args": ["000", execPath]],
                "undo": ["command": "chmod", "args": ["a=rx", execPath]]
            ],
            [
                "do": ["command": "chown", "args": ["root:wheel", execPath]],
                "undo": ["command": "chown", "args": ["\(getuid()):staff", execPath]]
            ],
            [
                "do": ["command": "chflags", "args": ["uchg", execPath]],
                "undo": ["command": "chflags", "args": ["nouchg", execPath]]
            ],
            [
                "do": ["command": "chflags", "args": ["uchg", hiddenAppRealURL.path]],
                "undo": ["command": "chflags", "args": ["nouchg", hiddenAppRealURL.path]]
            ]
        ]
    }

    private func authenticateAndOpenApp(
        lockedInfo: LockedAppInfo,
        hiddenAppRealURL: URL,
        execPath: String,
        unlockCmds: [[String: Any]],
        lockCmds: [[String: Any]]
    ) {
        guard sendToHelperBatch(unlockCmds) else {
            Logfile.launcher.error("Authentication or Unlock failed")
            exit(1)
        }

        let config = NSWorkspace.OpenConfiguration()
        config.arguments = CommandLine.arguments.dropFirst().map { String($0) }

        NSWorkspace.shared.open(hiddenAppRealURL, configuration: config) { [weak self] app, error in
            if let error = error {
                Logfile.launcher.error("Failed to open app: \(error.localizedDescription)")
                _ = self?.sendToHelperBatch(lockCmds)
                exit(1)
            }

            guard let app = app else {
                Logfile.launcher.error("No app returned from workspace open")
                _ = self?.sendToHelperBatch(lockCmds)
                exit(1)
            }

            Logfile.launcher.info("App opened: \(app.bundleIdentifier ?? "Unknown")")
            self?.waitForAppTermination(app: app, lockCmds: lockCmds)
        }
    }

    private func waitForAppTermination(app: NSRunningApplication, lockCmds: [[String: Any]]) {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if app.isTerminated {
                Logfile.launcher.info("App terminated, locking back...")
                _ = self?.sendToHelperBatch(lockCmds)
                timer.invalidate()
                exit(0)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run()
    }

    private func sendToHelperBatch(_ commandList: [[String: Any]]) -> Bool {
        let conn = NSXPCConnection(machServiceName: "com.TranPhuong319.AppLocker.Helper", options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: AppLockerHelperProtocol.self)
        conn.resume()

        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            Logfile.launcher.error("XPC error: \(error.localizedDescription)")
            result = false
            semaphore.signal()
        } as? AppLockerHelperProtocol

        guard let helperProxy = proxy else {
            Logfile.launcher.error("Failed to get helper proxy.")
            semaphore.signal()
            return false
        }

        performHelperAuthentication(proxy: helperProxy) { authSuccess in
            if authSuccess {
                helperProxy.sendBatch(commandList) { success, message in
                    if success {
                        Logfile.launcher.info("Success: \(message)")
                    } else {
                        Logfile.launcher.error("Failure: \(message)")
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
        conn.invalidate()
        return result
    }

    private func performHelperAuthentication(proxy: AppLockerHelperProtocol, completion: @escaping (Bool) -> Void) {
        let clientTag = KeychainHelper.Keys.appPublic
        if !KeychainHelper.shared.hasKey(tag: clientTag) {
            try? KeychainHelper.shared.generateKeys(tag: clientTag)
        }
        let clientNonce = Data.random(count: 32)
        guard let clientSig = KeychainHelper.shared.sign(data: clientNonce, tag: clientTag),
              let pubKeyData = KeychainHelper.shared.exportPublicKey(tag: clientTag) else {
            Logfile.launcher.error("Helper Auth: Failed to sign/export client data")
            completion(false)
            return
        }

        proxy.authenticate(clientNonce: clientNonce, clientSig: clientSig, clientPublicKey: pubKeyData) { sN, sS, sK, ok in
            guard ok, let sNonce = sN, let sSig = sS, let sKeyData = sK else {
                Logfile.launcher.error("Helper Auth: Server rejected or invalid response")
                completion(false)
                return
            }
            let combined = clientNonce + sNonce
            guard let serverKey = KeychainHelper.shared.createPublicKey(from: sKeyData) else {
                Logfile.launcher.error("Helper Auth: Failed to import server key")
                completion(false)
                return
            }
            if KeychainHelper.shared.verify(signature: sSig, originalData: combined, publicKey: serverKey) {
                Logfile.launcher.info("Helper Auth: Success")
                completion(true)
            } else {
                Logfile.launcher.error("Helper Auth: Server signature verification failed")
                completion(false)
            }
        }
    }

    func loadLockedAppInfos() -> [String: LockedAppInfo] {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AppLocker/config.plist")

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            Logfile.launcher.error("File Config does not exist")
            return [:]
        }

        do {
            let data = try Data(contentsOf: configURL)
            let decoded = try PropertyListDecoder().decode([String: LockedAppInfo].self, from: data)
            return decoded
        } catch {
            Logfile.launcher.error("Cannot read or decode config.plist: \(error.localizedDescription)")
            return [:]
        }
    }
}
