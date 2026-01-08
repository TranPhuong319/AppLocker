//
//  AppDelegate+Restart.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import Foundation
import AppKit

extension AppDelegate {
    func callUninstallHelper() {
        let conn = NSXPCConnection(
            machServiceName: "com.TranPhuong319.AppLocker.Helper",
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: AppLockerHelperProtocol.self)
        conn.resume()

        if let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            // EN: Ignore errors because helper will terminate itself after uninstall.
            // VI: Bỏ qua lỗi vì helper sẽ tự thoát sau khi gỡ cài đặt.
            Logfile.core.debug("XPC connection closed (expected): \(error.localizedDescription)")
        }) as? AppLockerHelperProtocol {
            proxy.uninstallHelper { _, _ in
                // EN: Fire-and-forget.
                // VI: Gửi và quên.
            }
        }

        // EN: Close connection immediately to avoid holding references.
        // VI: Đóng kết nối ngay để tránh giữ tham chiếu thừa.
        conn.invalidate()
    }

    func selfRemoveApp() {
        let bundlePath = Bundle.main.bundlePath
        let script = """
        rm -rf "\(bundlePath)"
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]

        do {
            try task.run()
            Logfile.core.info("App will remove itself at path: \(bundlePath)")
        } catch {
            Logfile.core.error("Failed to start self-removal: \(error.localizedDescription)")
        }
    }

    func removeConfig() {
        let fileManager = FileManager.default

        do {
            if fileManager.fileExists(atPath: ConfigStore.shared.configURL.path()) {
                try fileManager.removeItem(at: ConfigStore.shared.configURL)
                Logfile.core.info("The configuration folder has been successfully deleted.")

                let domain = Bundle.main.bundleIdentifier!
                UserDefaults.standard.removePersistentDomain(forName: domain)
                UserDefaults.standard.synchronize()

            }
        } catch {
            Logfile.core.error("Error deleting folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    func showRestartSheet() {
        let script = "tell application \"loginwindow\" to «event aevtrrst»"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        do {
            try task.run()
        } catch {
            print("Lỗi chạy osascript: \(error)")
        }
    }

    func restartApp(mode: AppMode?) {
        if mode == .es {
            manageAgent(plistName: plistName, action: .install)
        } else {
            let path = Bundle.main.bundlePath
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-n", path]
            try? task.run()
        }
        NSApp.terminate(nil)
    }
}
