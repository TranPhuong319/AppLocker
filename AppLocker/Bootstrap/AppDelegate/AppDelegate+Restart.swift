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
                    Logfile.core.error("Failed to move app to Trash: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
    }

    func removeConfig() -> Bool {
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.synchronize()
        }
        do {
            let url = ConfigStore.shared.configURL
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
            return true
        } catch {
            Logfile.core.error("Error deleting folder: \(error.localizedDescription)")
            return false
        }
    }

    func showRestartSheet() {
        let appleScriptSource = "tell application \"loginwindow\" to «event aevtrrst»"
        let restartProcess = Process()
        restartProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        restartProcess.arguments = ["-e", appleScriptSource]
        do {
            try restartProcess.run()
        } catch {
            Logfile.core.error("Error running osascript: \(error.localizedDescription)")
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
                Logfile.core.error("App restart error: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
