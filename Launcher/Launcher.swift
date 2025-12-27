//
//  Launcher.swift
//  Launcher
//
//  Created by Doe Phương on 24/07/2025.
//
//  EN: Helper launcher that authenticates and runs a hidden app, then re-locks it on exit.
//  VI: Trình khởi chạy hỗ trợ: xác thực và mở app ẩn, sau đó khóa lại khi thoát.
//

import AppKit
import Foundation
import ServiceManagement

// EN: Basic info for a locked app stored in config.
// VI: Thông tin cơ bản của app bị khóa lưu trong cấu hình.
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
    // EN: Files received from AppDelegate to open together with the app.
    // VI: Tệp nhận từ AppDelegate để mở cùng ứng dụng.
    var pendingOpenFileURLs: [URL] = []

    func run() {
// EN: Example of SMAppService daemon status check (unused here).
// VI: Ví dụ kiểm tra trạng thái daemon SMAppService (không dùng ở đây).
//        let plistName = "com.TranPhuong319.AppLockerHelper.plist"
//        let helperStatus = SMAppService.daemon(plistName: plistName).status
//        switch helperStatus {
//        case
//        }
        Logfile.launcher.info("Launcher started")
        Logfile.launcher.info("CommandLine args: \(CommandLine.arguments, privacy: .public)")

        // EN: Locate Resources folder inside this launcher bundle.
        // VI: Xác định thư mục Resources bên trong bundle của launcher.
        let resourcesURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        guard checkResourcesFolder(resourcesURL) else { exit(1) }

        // EN: Load locked app mapping (launcher path -> LockedAppInfo) from config.
        // VI: Nạp ánh xạ app bị khóa (đường dẫn launcher -> LockedAppInfo) từ config.
        let lockedApps = loadLockedAppInfos()

        do {
            // EN: Find .app bundles packaged inside Resources.
            // VI: Tìm các bundle .app được đóng gói trong Resources.
            let appURLs = try FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "app" }

            for appURL in appURLs {
                handleApp(appURL, lockedApps: lockedApps)
                return // EN: Only handle one app per launcher run. VI: Chỉ xử lý một app cho mỗi lần chạy launcher.
            }

            Logfile.launcher.error("Can't find the App locked in the Resources")
            exit(1)

        } catch {
            Logfile.launcher.error("Error when approving the Resources folder: \(error)")
            exit(1)
        }
    }

    // MARK: - Helpers / Trợ giúp

    // EN: Ensure the Resources folder exists.
    // VI: Đảm bảo thư mục Resources tồn tại.
    private func checkResourcesFolder(_ url: URL) -> Bool {
        if !FileManager.default.fileExists(atPath: url.path) {
            Logfile.launcher.error("Folder not found: \(url.path, privacy: .public)")
            return false
        }
        return true
    }

    // EN: Resolve the hidden real app path and kick off authentication/open.
    // VI: Xác định đường dẫn app thật (bị ẩn) và thực thi xác thực/mở app.
    private func handleApp(_ appURL: URL, lockedApps: [String: LockedAppInfo]) {
        let appName = appURL.deletingPathExtension().lastPathComponent

        // EN: Use the launcherPath from config.plist by matching name.
        // VI: Dùng launcherPath từ config.plist bằng cách khớp theo tên.
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

    // EN: Commands to temporarily unlock app and its exec file.
    // VI: Các lệnh để tạm thời mở khóa app và file thực thi.
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

    // EN: Commands to re-lock the exec file and app bundle.
    // VI: Các lệnh để khóa lại file thực thi và bundle ứng dụng.
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

    // EN: Authenticate user, open the hidden app, and re-lock after it quits.
    // VI: Xác thực người dùng, mở app ẩn, và khóa lại sau khi app thoát.
    private func authenticateAndOpenApp(lockedInfo: LockedAppInfo,
                                        hiddenAppRealURL: URL,
                                        execPath: String,
                                        unlockCmds: [[String: Any]],
                                        lockCmds: [[String: Any]]) {
        guard sendToHelperBatch(unlockCmds) else {
            Logfile.launcher.error("Cannot unlock the Exec file")
            exit(1)
        }
        AuthenticationManager.authenticate(reason: "authentication to open".localized) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    self.openApplication(lockedInfo: lockedInfo,
                                    hiddenAppRealURL: hiddenAppRealURL,
                                    lockCmds: lockCmds)
                } else {
                    Logfile.launcher.error("Failure authenticity: \(errorMessage ?? "Unknown error", privacy: .public)")
                    exit(1)
                }
            }
        }
    }

    // EN: Open the app with optional files/URLs and monitor termination.
    // VI: Mở app kèm tệp/URL tùy chọn và theo dõi khi app thoát.
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

    // EN: Determine a file/URL to open from arguments or saved list.
    // VI: Xác định tệp/URL cần mở từ tham số hoặc danh sách đã lưu.
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

    // EN: Wait for the app to quit, then re-lock its files.
    // VI: Chờ ứng dụng thoát, sau đó khóa lại các tệp.
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

    // EN: (Unused) Alternative result handler for opening app.
    // VI: (Không dùng) Hàm xử lý kết quả mở app thay thế.
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

    // EN: Send a batch of privileged commands to the helper via XPC.
    // VI: Gửi một loạt lệnh đặc quyền tới helper qua XPC.
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

        proxy?.sendBatch(commandList) { success, message in
            if success {
                Logfile.launcher.info("Success: \(message, privacy: .public)")
            } else {
                Logfile.launcher.error("Failure: \(message, privacy: .public)")
            }
            result = success
            semaphore.signal()
        }

        semaphore.wait()
        conn.invalidate()
        return result
    }

    // EN: Read config.plist for locked apps information.
    // VI: Đọc config.plist để lấy thông tin ứng dụng bị khóa.
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
