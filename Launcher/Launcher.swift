//
//  Launcher.swift
//  Launcher
//
//  Created by Doe Phương on 24/07/2025.
//


import Foundation
import AppKit

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
    
    func run() {
        guard let resourcesURL = Bundle.main.resourceURL else {
            print("❌ Không thể truy cập resourceURL")
            exit(1)
        }

        let lockedApps = loadLockedAppInfos()

        do {
            let appURLs = try FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "app" }

            for appURL in appURLs {
                let appName = appURL.deletingPathExtension().lastPathComponent

                // 🔍 Nếu app tên ".locked_TenApp", ta lấy "TenApp"
                guard appName.hasPrefix(".locked_") else { continue }
                let realAppName = appName.replacingOccurrences(of: ".locked_", with: "")
                let disguisedAppPath = "/Applications/\(realAppName).app"

                guard let lockedInfo = lockedApps[disguisedAppPath] else {
                    print("⚠️ Không tìm thấy info cho: \(disguisedAppPath)")
                    continue
                }


                let realAppURL = appURL.deletingLastPathComponent().appendingPathComponent("\(lockedInfo.name).app")
                let execPath = realAppURL
                    .appendingPathComponent("Contents/MacOS/\(lockedInfo.execFile)")
                    .path

                print("🔓 App cần mở khóa: \(lockedInfo.name), exec: \(lockedInfo.execFile)")
                let uid = getuid()
                let gid = getgid()

                // 1. Mở quyền file
                let unlockCmds: [[String: Any]] = [
                    ["command": "chflags", "args": ["nouchg", execPath]],
                    ["command": "chmod", "args": ["a=rx", execPath]],
                    ["command": "chown", "args": ["\(uid):\(gid)", execPath]],
                ]
                let lockCmds: [[String: Any]] = [
                    ["command": "chmod", "args": ["000", execPath]],
                    ["command": "chown", "args": ["root:wheel", execPath]],
                    ["command": "chflags", "args": ["uchg", execPath]],
                ]

                guard sendToHelperBatch(unlockCmds) else {
                    print("❌ Không thể mở khóa file exec")
                    exit(1)
                }

                // 2. Xác thực
                AuthenticationManager.authenticate(reason: "xác thực để mở ứng dụng đã bị khoá") { success, errorMessage in
                    DispatchQueue.main.async {
                        if success {
                            print("✅ Xác thực thành công, đang mở ứng dụng...")

                            let config = NSWorkspace.OpenConfiguration()
                            NSWorkspace.shared.openApplication(at: realAppURL, configuration: config) { runningApp, err in
                                if let err = err {
                                    print("❌ Không thể mở app: \(err)")
                                    exit(1)
                                }

                                guard let runningApp = runningApp else {
                                    print("❌ Không lấy được tiến trình ứng dụng")
                                    exit(1)
                                }

                                DispatchQueue.global().async {
                                    while !runningApp.isTerminated {
                                        sleep(1)
                                    }

                                    print("📦 App đã thoát. Đang khoá lại file...")

                                    if self.sendToHelperBatch(lockCmds) {
                                        print("✅ Đã khoá lại file exec")
                                        exit(0)
                                    } else {
                                        print("❌ Không thể khoá lại file")
                                        exit(1)
                                    }
                                }
                            }

                        } else {
                            print("❌ Xác thực thất bại:", errorMessage ?? "Không rõ lỗi")
                            if self.sendToHelperBatch(lockCmds) {
                                print("✅ Đã khoá lại file exec")
                            }
                            exit(1)
                        }
                    }
                }

                return // chỉ chạy 1 app
            }

            print("❌ Không tìm thấy app bị khoá trong Resources")
            exit(1)

        } catch {
            print("❌ Lỗi khi duyệt thư mục Resources: \(error)")
            exit(1)
        }
    }

    private func sendToHelperBatch(_ commandList: [[String: Any]]) -> Bool {
        let conn = NSXPCConnection(machServiceName: "com.TranPhuong319.AppLockerHelper", options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: AppLockerHelperProtocol.self)
        conn.resume()

        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            print("❌ XPC error:", error.localizedDescription)
            result = false
            semaphore.signal()
        } as? AppLockerHelperProtocol

        proxy?.sendBatch(commandList) { success, message in
            print(success ? "✅ Thành công:" : "❌ Thất bại:", message)
            result = success
            semaphore.signal()
        }

        semaphore.wait()
        conn.invalidate()
        return result
    }

    private func loadLockedAppInfos() -> [String: LockedAppInfo] {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AppLocker/config.plist")

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            print("❌ File config không tồn tại")
            return [:]
        }

        do {
            let data = try Data(contentsOf: configURL)
            print("📦 Raw data size:", data.count)
            
            if let plistStr = String(data: data, encoding: .utf8) {
                print("📜 Nội dung config.plist:\n\(plistStr)")
            }

            let decoded = try PropertyListDecoder().decode([String: LockedAppInfo].self, from: data)
            return decoded
        } catch {
            print("❌ Không thể đọc hoặc decode config.plist: \(error.localizedDescription)")
            return [:]
        }
    }
}
