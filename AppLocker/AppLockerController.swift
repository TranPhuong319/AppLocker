import Foundation
import AppKit

class AppLockerController {
    static let shared = AppLockerController()
    private var observer: Any?

    func startMonitoring() {
        // Lắng nghe ngay khi 1 app mới launch
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleLaunch(notification: note)
        }
    }

    private func handleLaunch(notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            let bundleID = app.bundleIdentifier
        else { return }

        let manager = LockedAppsManager()
        // Nếu app này nằm trong danh sách khóa
        if manager.isLocked(bundleID) {
            // Nếu trước đó chưa unlock
            if !AppUnlockState.shared.isUnlocked(bundleID: bundleID) {
                // Yêu cầu xác thực
                if AuthenticationManager.authenticate() {
                    // mark đã unlock
                    AppUnlockState.shared.markUnlocked(bundleID: bundleID)
                } else {
                    // kill ngay lập tức
                    app.forceTerminate()
                    print("🛑 Đã chặn và kill \(bundleID)")
                }
            }
        }
    }

    func stopMonitoring() {
        if let obs = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }
}
