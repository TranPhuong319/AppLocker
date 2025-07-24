//
//  AppLockerController.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import Foundation
import AppKit

class AppLockerController {
    static let shared = AppLockerController()
    private var timer: Timer?

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.checkRunningApps()
        }
    }

    func checkRunningApps() {
        let manager = LockedAppsManager()
        let running = NSWorkspace.shared.runningApplications

        for app in running {
            guard let bundleID = app.bundleIdentifier else { continue }

            if manager.isLocked(bundleID) {
                if !AuthenticationManager.authenticate() {
                    app.forceTerminate()
                }
            }
        }
    }
}
