//
//  AppLockerXPCService.swift
//  AppLocker
//
//  Created by Doe Phương on 26/07/2025.
//


import Foundation
import AppKit

class AppLockerXPCService: NSObject, AppLockerXPCProtocol {
    func handleLaunchRequest(fromPID pid: Int32, appPath: String, withReply reply: @escaping (Bool) -> Void) {
        print("🔒 Nhận yêu cầu mở app: \(appPath), từ PID: \(pid)")
        
        let fileURL = URL(fileURLWithPath: appPath)
        let folderURL = fileURL.deletingLastPathComponent()
        let execName = fileURL.lastPathComponent

        let stubURL = folderURL.appendingPathComponent("stub")
        let stubLauncherURL = folderURL.appendingPathComponent("stub.launcher")
        let realURL = folderURL.appendingPathComponent(execName + ".real")
        let unlockedURL = folderURL.appendingPathComponent(execName)
        
        // 1. Kill launcher
        kill(pid, SIGKILL)

        // 2. Đổi tên file
        do {
            try FileManager.default.moveItem(at: stubURL, to: stubLauncherURL)
            try FileManager.default.moveItem(at: realURL, to: unlockedURL)
        } catch {
            print("❌ Rename lỗi: \(error)")
            reply(false)
            return
        }

        // 3. chmod 755 file thực thi
        chmod(unlockedURL.path, S_IRUSR | S_IWUSR | S_IXUSR | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH)

        // 4. Mở app
        NSWorkspace.shared.open(folderURL.deletingLastPathComponent())

        // 5. Theo dõi tiến trình app thực thi
        DispatchQueue.global().async {
            let runningApp = self.findAppProcess(executablePath: unlockedURL.path)
            guard let pid = runningApp?.processIdentifier else {
                print("⚠️ Không tìm thấy process app sau khi mở")
                reply(false)
                return
            }

            print("▶️ App đang chạy với PID: \(pid)")

            // Chờ app kết thúc
            var wait_status: Int32 = 0
            waitpid(pid, &wait_status, 0)

            print("✅ App kết thúc. Đặt lại quyền và cấu trúc file")

            // 6. chmod 000 + revert rename
            chmod(unlockedURL.path, 0o000)

            do {
                try FileManager.default.moveItem(at: unlockedURL, to: realURL)
                try FileManager.default.moveItem(at: stubLauncherURL, to: stubURL)
            } catch {
                print("❌ Lỗi revert file: \(error)")
            }

            reply(true)
        }
    }

    /// Tìm tiến trình đang chạy ứng với file thực thi
    private func findAppProcess(executablePath: String) -> NSRunningApplication? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: nil)
        for app in apps {
            if let path = app.executableURL?.path, path == executablePath {
                return app
            }
