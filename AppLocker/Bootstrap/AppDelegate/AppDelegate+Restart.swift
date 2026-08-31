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
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        do {
            let targetURL = purgeAll ? ConfigStore.baseDirectoryURL : ConfigStore.shared.userDirectoryURL
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            return true
        } catch {
            Logfile.app.error("[Lifecycle] Error deleting config directory: \(error.localizedDescription)")
            return false
        }
    }

    func restartApp() {
        let bundleURL = Bundle.main.bundleURL
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
