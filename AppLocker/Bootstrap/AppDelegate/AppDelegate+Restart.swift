//
//  AppDelegate+Restart.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit
import Foundation

extension AppDelegate {

    func selfRemoveApp() async -> Bool {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, error in
                if let error {
                    Logfile.app.error("[Lifecycle] Failed to move app to Trash: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
    }

    func removeConfig(purgeAll: Bool = false) -> Bool {
        ConfigStore.shared.removeConfig(purgeAll: purgeAll)
    }

    func restartApp(at bundleURL: URL = Bundle.main.bundleURL) {
        let pid = ProcessInfo.processInfo.processIdentifier

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["-waitForPID", "\(pid)"]

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if let error = error {
                Logfile.app.error("[Lifecycle] App restart error: \(error.localizedDescription)")
            }
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
