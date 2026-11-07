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
        do {
            _ = try await NSWorkspace.shared.recycle([Bundle.main.bundleURL])
            return true
        } catch {
            Logfile.app.error("[Lifecycle] Failed to move app to Trash: \(error.localizedDescription)")
            return false
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

        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
            } catch {
                Logfile.app.error("[Lifecycle] App restart error: \(error.localizedDescription)")
            }
            NSApp.terminate(nil)
        }
    }
}
