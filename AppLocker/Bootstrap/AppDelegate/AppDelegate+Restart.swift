//
//  AppDelegate+Restart.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit
import Foundation

extension AppDelegate {

    func selfRemoveApp() {
        let bundleURL = Bundle.main.bundleURL

        do {
            try FileManager.default.trashItem(at: bundleURL, resultingItemURL: nil)
            Logfile.core.info("App successfully moved to Trash")
        } catch {
            Logfile.core.error("Failed to move app to Trash: \(error.localizedDescription, privacy: .public)")
        }
    }

    func removeConfig() {
        let sharedFileManager = FileManager.default

        // Always remove UserDefaults regardless of whether config file exists
        if let bundleIdentifierDomain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifierDomain)
            UserDefaults.standard.synchronize()
            Logfile.core.info("UserDefaults cleared for domain: \(bundleIdentifierDomain)")
        }

        do {
            // Check if config file exists before trying to delete the folder
            /*
               ConfigStore.shared.configURL points to .../AppLocker/config.plist
               deletingLastPathComponent() points to .../AppLocker/
            */
            if sharedFileManager.fileExists(atPath: ConfigStore.shared.configURL.path()) {
                try sharedFileManager.removeItem(
                    at: ConfigStore.shared.configURL.deletingLastPathComponent())
                Logfile.core.info("The configuration folder has been successfully deleted.")
            }
        } catch {
            Logfile.core.error(
                "Error deleting folder: \(error.localizedDescription)")
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

    func restartApp(completion: (() -> Void)? = nil) {
        manageAgent(plistName: plistName, action: .install)
        manageHelperLoginItem(
            helperBundleID: loginItem,
            action: .install
        )
        completion?()
        NSApp.terminate(nil)
    }
}
