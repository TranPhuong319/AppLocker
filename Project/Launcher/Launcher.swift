//
//  Launcher.swift
//  Launcher
//
//  Created by Doe Phương on 24/07/2025.
//

import AppKit
import Foundation

struct LockedAppInfo: Codable {
    let name: String
    let execFile: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case execFile = "ExecFile"
    }
}

class Launcher {
    static let shared = Launcher()
    // ✅ lưu file nhận được từ AppDelegate
    var pendingOpenFileURLs: [URL] = []

    func run() {
        Logfile.launcher.info("🚀 Launcher started")
        Logfile.launcher.info("📝 CommandLine args: \(CommandLine.arguments, privacy: .public)")
        let resourcesURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")

        guard FileManager.default.fileExists(atPath: resourcesURL.path) else {
            Logfile.launcher.error("❌ Folder not found: \(resourcesURL.path, privacy: .public)")
            exit(1)
        }

        let lockedApps = loadLockedAppInfos()

        do {
            let appURLs = try FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "app" }

            for appURL in appURLs {
                let appName = appURL.deletingPathExtension().lastPathComponent

                // 🔍 Nếu app tên ".locked_TenApp", ta lấy "TenApp"
//                guard appName.hasPrefix(".locked_") else { continue }
                let LauncherPath = "/Applications/\(appName).app"
                let hiddenAppRealURL  = URL(fileURLWithPath:"/Applications/.\(appName).app")

                guard let lockedInfo = lockedApps[LauncherPath] else {
                    Logfile.launcher.warning("⚠️ Can't find info for: \(LauncherPath)")
                    continue
                }

                let execPath = hiddenAppRealURL.appendingPathComponent("Contents/MacOS/\(lockedInfo.execFile)").path

                Logfile.launcher.info("🔓 App to unlock: \(lockedInfo.name), Exec: \(lockedInfo.execFile)")
                let uid = getuid()
                let gid = getgid()

                // 1. Mở quyền file
                let unlockCmds: [[String: Any]] = [
                    ["command": "chflags", "args": ["nouchg", hiddenAppRealURL.path]],
                    ["command": "chflags", "args": ["nouchg", execPath]],
                    ["command": "chmod", "args": ["a=rx", execPath]],
                    ["command": "chown", "args": ["\(uid):\(gid)", execPath]],
                ]
                let lockCmds: [[String: Any]] = [
                    ["command": "chmod", "args": ["000", execPath]],
                    ["command": "chown", "args": ["root:wheel", execPath]],
                    ["command": "chflags", "args": ["uchg", execPath]],
                    ["command": "chflags", "args": ["uchg", hiddenAppRealURL.path]],
                ]

                guard sendToHelperBatch(unlockCmds) else {
                    Logfile.launcher.error("❌ Cannot unlock the Exec file")
                    exit(1)
                }

                // 2. Xác thực
                AuthenticationManager.authenticate(reason: "authentication to open".localized) { success, errorMessage in
                    DispatchQueue.main.async {
                        if success {
                            Logfile.launcher.info("✅ Successful authentication, opening application...")

                            let config = NSWorkspace.OpenConfiguration()
                            var fileURLToOpen: URL? = nil

                            if let fromDelegate = Launcher.shared.pendingOpenFileURLs.first {
                                fileURLToOpen = fromDelegate
                                Logfile.launcher.info("📂 Open with file \(fromDelegate.path)")
                            } else {
                                let args = CommandLine.arguments
                                if args.count > 1 {
                                    let arg = args[1]
                                    if FileManager.default.fileExists(atPath: arg) {
                                        fileURLToOpen = URL(fileURLWithPath: arg)
                                        Logfile.launcher.info("📂 Open with file: \(fileURLToOpen!.path)")
                                    } else if let url = URL(string: arg), url.scheme != nil {
                                        fileURLToOpen = url
                                        Logfile.launcher.info("🌐 Open with URL: \(url.absoluteString)")
                                    }
                                }
                            }
                            

                            let openHandler: (NSRunningApplication?, Error?) -> Void = { runningApp, err in
                                if let err = err {
                                    Logfile.launcher.error("❌ Can't open the app: \(err)")
                                    exit(1)
                                }

                                guard let runningApp = runningApp else {
                                    Logfile.launcher.error("❌ Can't get the application process")
                                    exit(1)
                                }

                                DispatchQueue.global().async {
                                    while !runningApp.isTerminated {
                                        sleep(1)
                                    }

                                    Logfile.launcher.info("📦 App closed. Locking the file ...")

                                    if self.sendToHelperBatch(lockCmds) {
                                        Logfile.launcher.info("✅ Lock the Exec file")
                                        exit(0)
                                    } else {
                                        Logfile.launcher.error("❌ Can't lock the file")
                                        exit(1)
                                    }
                                }
                            }

                            if !Launcher.shared.pendingOpenFileURLs.isEmpty {
                                // ✅ Nếu delegate đã nhận được file(s)
                                Logfile.launcher.info("📂 Open with pending files: \(Launcher.shared.pendingOpenFileURLs.map(\.path))")
                                NSWorkspace.shared.open(Launcher.shared.pendingOpenFileURLs,
                                                        withApplicationAt: hiddenAppRealURL,
                                                        configuration: config,
                                                        completionHandler: openHandler)
                            } else if let fileURLToOpen = fileURLToOpen {
                                // ✅ Nếu chỉ có 1 file/URL từ args
                                NSWorkspace.shared.open([fileURLToOpen],
                                                        withApplicationAt: hiddenAppRealURL,
                                                        configuration: config,
                                                        completionHandler: openHandler)
                            } else {
                                // ✅ Không có file → chỉ mở app
                                NSWorkspace.shared.openApplication(at: hiddenAppRealURL,
                                                                   configuration: config,
                                                                   completionHandler: openHandler)
                            }

                        } else {
                            Logfile.launcher.error("❌ Failure authenticity: \(errorMessage ?? "Unknown error", privacy: .public)")
                            if self.sendToHelperBatch(lockCmds) {
                                Logfile.launcher.info("✅ Lock the Exec file")
                            }
                            exit(1)
                        }
                    }
                }

                return // chỉ chạy 1 app
            }

            Logfile.launcher.error("❌ Can't find the App locked in the Resources")
            exit(1)

        } catch {
            Logfile.launcher.error("❌ Error when approving the Resources folder: \(error)")
            exit(1)
        }
    }

    private func handleOpenResult(runningApp: NSRunningApplication?, err: Error?, lockCmds: [[String: Any]]) {
        if let err = err {
            Logfile.launcher.error("❌ Can't open the app: \(err.localizedDescription)")
            exit(1)
        }

        guard let runningApp = runningApp else {
            Logfile.launcher.error("❌ Can't get the application process")
            exit(1)
        }

        DispatchQueue.global().async {
            while !runningApp.isTerminated {
                sleep(1)
            }

            Logfile.launcher.info("📦 App escaped. Locking the file ...")

            if self.sendToHelperBatch(lockCmds) {
                Logfile.launcher.info("✅ Lock the Exec file")
                exit(0)
            } else {
                Logfile.launcher.error("❌ Can't lock the file")
                exit(1)
            }
        }
    }

    private func sendToHelperBatch(_ commandList: [[String: Any]]) -> Bool {
        let conn = NSXPCConnection(machServiceName: "com.TranPhuong319.AppLockerHelper", options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: AppLockerHelperProtocol.self)
        conn.resume()

        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            Logfile.launcher.error("❌ XPC error: \(error.localizedDescription)")
            result = false
            semaphore.signal()
        } as? AppLockerHelperProtocol

        proxy?.sendBatch(commandList) { success, message in
            if success {
                Logfile.launcher.info("✅ Success: \(message, privacy: .public)")
            } else {
                Logfile.launcher.error("❌ Failure: \(message, privacy: .public)")
            }
            result = success
            semaphore.signal()
        }

        semaphore.wait()
        conn.invalidate()
        return result
    }

    func loadLockedAppInfos() -> [String: LockedAppInfo] {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AppLocker/config.plist")

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            Logfile.launcher.error("❌ File Config does not exist")
            return [:]
        }

        do {
            let data = try Data(contentsOf: configURL)
            Logfile.launcher.info("📦 Raw data size: \(data.count)")

            if let plistStr = String(data: data, encoding: .utf8) {
                Logfile.launcher.info("📜 Config.plist content:\n\(plistStr)")
            }

            let decoded = try PropertyListDecoder().decode([String: LockedAppInfo].self, from: data)
            return decoded
        } catch {
            Logfile.launcher.error("❌ Cannot read or decode config.plist: \(error.localizedDescription)")
            return [:]
        }
    }
}
