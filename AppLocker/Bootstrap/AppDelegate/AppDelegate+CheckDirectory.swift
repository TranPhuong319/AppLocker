//
//  AppDelegate+CheckDirectory.swift
//  AppLocker
//
//  Created by Doe Phương on 28/2/26.
//

import Foundation
import AppKit

extension AppDelegate {
    /// Returns `true` when relocation or termination was triggered and launch setup must abort.
    @discardableResult
    func checkAndMoveToApplications() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        guard !AppDirectoryPolicy.isAllowedLocation(for: bundleURL) else { return false }

        let displayPath = AppDirectoryPolicy.abbreviatedDisplayPath(for: bundleURL)

        let response = AlertShow.show(
            title: String(localized: "Requires running in the Applications folder"),
            message: String(localized:
            """
            The currently running application is at \(displayPath).

            AppLocker must be moved to the /Applications folder to function correctly.
            """
                           ),
            style: .critical,
            buttons: [String(localized: "Move to Applications"), String(localized: "Quit")],
            cancelIndex: 1,
            defaultIndex: 0
        )

        if case .button(index: 0, _) = response {
            moveToApplicationsAndRelaunch()
        } else {
            NSApp.terminate(nil)
        }
        return true
    }

    private func moveToApplicationsAndRelaunch() {
        let bundleURL = Bundle.main.bundleURL
        let result = AppDirectoryPolicy.relocate(
            from: bundleURL,
            runPrivilegedScript: executePrivilegedMoveScript
        )

        switch result {
        case let .relocatedViaFileManager(destination, trashError):
            if let trashError {
                Logfile.app.warning(
                    "[DirectoryCheck] Failed to trash bundle: \(trashError, privacy: .public)"
                )
            }
            Logfile.app.info("[DirectoryCheck] Moved application to /Applications via FileManager. Restarting…")
            restartApp(at: destination)

        case let .relocatedViaPrivilegedScript(destination, fileManagerError):
            Logfile.app.warning(
                """
                [DirectoryCheck] FileManager move failed: \(fileManagerError, privacy: .public), \
                falling back to privileged AppleScript
                """
            )
            Logfile.app.info(
                "[DirectoryCheck] Moved application to /Applications via AppleScript. Restarting…"
            )
            restartApp(at: destination)

        case let .failed(fileManagerError, scriptError):
            Logfile.app.warning(
                """
                [DirectoryCheck] FileManager move failed: \(fileManagerError, privacy: .public), \
                falling back to privileged AppleScript
                """
            )
            Logfile.app.error(
                "[DirectoryCheck] AppleScript privileged move failed: \(scriptError ?? "Unknown", privacy: .public)"
            )
            AlertShow.showInfo(
                title: String(localized: "Failed to Move Application"),
                message: String(
                    localized: """
                    Could not move the application to /Applications automatically. \
                    Please move it manually to continue.
                    """
                ),
                style: .critical
            )
            NSApp.terminate(nil)
        }
    }

    private func executePrivilegedMoveScript(_ scriptSource: String) -> String? {
        guard let scriptObject = NSAppleScript(source: scriptSource) else {
            return "Failed to initialize NSAppleScript"
        }
        var errorDict: NSDictionary?
        _ = scriptObject.executeAndReturnError(&errorDict)
        return errorDict.map { String(describing: $0) }
    }
}
