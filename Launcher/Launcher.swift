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
        case name = "name"
        case execFile = "execFile"
    }
}

class Launcher {
    static let shared = Launcher()
    var pendingOpenFileURLs: [URL] = []

    func run() {
        Logfile.launcher.info("Launcher started")
        Logfile.launcher.pInfo("CommandLine args: \(CommandLine.arguments)")

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

    // MARK: - Helpers / Trợ giúp
    private func checkResourcesFolder(_ url: URL) -> Bool {
        if !FileManager.default.fileExists(atPath: url.path) {
            Logfile.launcher.pError("Folder not found: \(url.path)")
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

    private func authenticateAndOpenApp(lockedInfo: LockedAppInfo,
                                        hiddenAppRealURL: URL,
                                        execPath: String,
                                        unlockCmds: [[String: Any]],
                                        lockCmds: [[String: Any]]) {
        guard sendToHelperBatch(unlockCmds) else {
            Logfile.launcher.error("Cannot unlock the Exec file")
            exit(1)
        }
        AuthenticationManager.authenticate(
            reason: String(localized: "authentication to open")
        ) { success, error in
            if success {
                self.openApplication(
                    lockedInfo: lockedInfo,
                    hiddenAppRealURL: hiddenAppRealURL,
                    lockCmds: lockCmds
                )
            } else {
                let message = error?.localizedDescription ?? "Unknown error"
                Logfile.launcher.pError("Failure authenticity: \(message)")
                exit(1)
            }
        }
    }

    private func openApplication(lockedInfo: LockedAppInfo,
                                 hiddenAppRealURL: URL,
                                 lockCmds: [[String: Any]]) {
        Logfile.launcher.info("Successful authentication, opening application...")

        let config = NSWorkspace.OpenConfiguration()
        let fileURLToOpen = resolveFileToOpen()

        let openHandler: (NSRunningApplication?, Error?) -> Void = { runningApp, err in
            if let err = err {
                Logfile.launcher.error("Can't open the app: \(err)")
                exit(1)
            }
            guard let runningApp = runningApp else {
                Logfile.launcher.error("Can't get the application process")
                exit(1)
            }
            self.monitorAppTermination(runningApp, lockCmds: lockCmds)
        }

        if !Launcher.shared.pendingOpenFileURLs.isEmpty {
            Logfile.launcher.info("Open with pending files: \(Launcher.shared.pendingOpenFileURLs.map(\.path))")
            NSWorkspace.shared.open(Launcher.shared.pendingOpenFileURLs,
                                    withApplicationAt: hiddenAppRealURL,
                                    configuration: config,
                                    completionHandler: openHandler)
        } else if let fileURLToOpen = fileURLToOpen {
            NSWorkspace.shared.open([fileURLToOpen],
                                    withApplicationAt: hiddenAppRealURL,
                                    configuration: config,
                                    completionHandler: openHandler)
        } else {
            NSWorkspace.shared.openApplication(at: hiddenAppRealURL,
                                               configuration: config,
                                               completionHandler: openHandler)
        }
    }

    private func resolveFileToOpen() -> URL? {
        if let fromDelegate = Launcher.shared.pendingOpenFileURLs.first {
            Logfile.launcher.info("Open with file \(fromDelegate.path)")
            return fromDelegate
        }
        let args = CommandLine.arguments
        if args.count > 1 {
            let arg = args[1]
            if FileManager.default.fileExists(atPath: arg) {
                let url = URL(fileURLWithPath: arg)
                Logfile.launcher.info("Open with file: \(url.path)")
                return url
            } else if let url = URL(string: arg), url.scheme != nil {
                Logfile.launcher.info("Open with URL: \(url.absoluteString)")
                return url
            }
        }
        return nil
    }

    private func monitorAppTermination(_ runningApp: NSRunningApplication,
                                       lockCmds: [[String: Any]]) {
        DispatchQueue.global().async {
            while !runningApp.isTerminated { sleep(1) }
            Logfile.launcher.info("App closed. Locking the file ...")
            if self.sendToHelperBatch(lockCmds) {
                Logfile.launcher.info("Lock the Exec file")
                exit(0)
            } else {
                Logfile.launcher.error("Can't lock the file")
                exit(1)
            }
        }
    }

    private func handleOpenResult(runningApp: NSRunningApplication?, err: Error?, lockCmds: [[String: Any]]) {
        if let err = err {
            Logfile.launcher.error("Can't open the app: \(err.localizedDescription)")
            exit(1)
        }

        guard let runningApp = runningApp else {
            Logfile.launcher.error("Can't get the application process")
            exit(1)
        }

        DispatchQueue.global().async {
            while !runningApp.isTerminated {
                sleep(1)
            }

            Logfile.launcher.info("App escaped. Locking the file ...")

            if self.sendToHelperBatch(lockCmds) {
                Logfile.launcher.info("Lock the Exec file")
                exit(0)
            } else {
                Logfile.launcher.error("Can't lock the file")
                exit(1)
            }
        }
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

        // ---------------------------------------------------------
        // AUTH Handshake before sending commands
        // ---------------------------------------------------------
        func doAuth(completion: @escaping (Bool) -> Void) {
            // Launcher uses its own key or shares App key?
            // Ideally Launcher should have its own key or share keychain group.
            // Since we use isolated keychains (Bundle ID), Launcher needs its own key pair.
            // Tag: com.TranPhuong319.AppLocker.Launcher.public
            // BUT "KeychainHelper.Keys.appPublic" is constant string "com.TranPhuong319.AppLocker.public"
            // If Launcher has different Bundle ID, it stores in different keychain area.
            // We can reuse the same Tag string because the Service Name (Bundle ID) isolates them.

            let clientTag = KeychainHelper.Keys.appPublic // Reusing constant, context isolated by service name

            // 1. Ensure Client Keys
            if !KeychainHelper.shared.hasKey(tag: clientTag) {
                 try? KeychainHelper.shared.generateKeys(tag: clientTag)
            }

            // 2. Prepare Auth Data
            let clientNonce = Data.random(count: 32)
            guard let clientSig = KeychainHelper.shared.sign(data: clientNonce, tag: clientTag),
                  let pubKeyData = KeychainHelper.shared.exportPublicKey(tag: clientTag) else {
                Logfile.launcher.error("Helper Auth: Failed to sign/export client data")
                completion(false)
                return
            }

            proxy?.authenticate(clientNonce: clientNonce, clientSig: clientSig, clientPublicKey: pubKeyData) { serverNonce, serverSig, serverPubKey, success in
                 guard success, let sNonce = serverNonce, let sSig = serverSig, let sKeyData = serverPubKey else {
                     Logfile.launcher.error("Helper Auth: Server rejected or invalid response")
                     completion(false)
                     return
                 }

                 // 3. Verify Server
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

        // Execute Auth then Batch
        doAuth { authSuccess in
            if authSuccess {
                proxy?.sendBatch(commandList) { success, message in
                    if success {
                        Logfile.launcher.pInfo("Success: \(message)")
                    } else {
                        Logfile.launcher.pError("Failure: \(message)")
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

    func loadLockedAppInfos() -> [String: LockedAppInfo] {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AppLocker/config.plist")

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            Logfile.launcher.error("File Config does not exist")
            return [:]
        }

        do {
            let data = try Data(contentsOf: configURL)
            Logfile.launcher.info("Raw data size: \(data.count)")

            if let plistStr = String(data: data, encoding: .utf8) {
                Logfile.launcher.info("Config.plist content:\n\(plistStr)")
            }

            let decoded = try PropertyListDecoder().decode([String: LockedAppInfo].self, from: data)
            return decoded
        } catch {
            Logfile.launcher.error("Cannot read or decode config.plist: \(error.localizedDescription)")
            return [:]
        }
    }
}

extension Data {
    static func random(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        return data
    }
}
