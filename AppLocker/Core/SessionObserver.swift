import Cocoa

final class SessionObserver {
    init() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            self,
            selector: #selector(sessionDidLogin),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(sessionDidLogout),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
    }

    @objc private func sessionDidLogin(_ noti: Notification) {
        // User login vào session
    }

    @objc private func sessionDidLogout(_ noti: Notification) {
        // User logout khỏi session
    }
}
