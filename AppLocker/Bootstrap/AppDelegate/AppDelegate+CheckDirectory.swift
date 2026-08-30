//
//  AppDelegate+CheckDirectory.swift
//  AppLocker
//
//  Created by Doe Phương on 28/2/26.
//

import Foundation
import AppKit

extension AppDelegate {
    func checkAndMoveToApplications() {
        let bundleURL = Bundle.main.bundleURL

        let allowedPaths = [
            "/Applications"
        ]

        let currentPath = bundleURL.deletingLastPathComponent().path

        let isAllowed = allowedPaths.contains { path in
            currentPath == path || currentPath.hasPrefix(path)
        }

        if !isAllowed {
            // Hiển thị đầu, cuối bỏ phần giữa
            var displayPath = (currentPath as NSString).abbreviatingWithTildeInPath
            if displayPath.count > 50 {
                let components = displayPath.components(separatedBy: "/")
                if components.count > 4 {
                    let firstPart = components.prefix(2).joined(separator: "/")
                    let lastPart = components.suffix(2).joined(separator: "/")
                    displayPath = "\(firstPart)/.../\(lastPart)"
                }
            }

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
        }
    }

    private func relaunchApp(from url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        let pid = ProcessInfo.processInfo.processIdentifier
        configuration.arguments = ["-waitForPID", "\(pid)"]

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error = error {
                Logfile.app.error(
                    "[DirectoryCheck] Application restart error in Applications: \(error.localizedDescription)"
                )
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    private func moveToApplicationsAndRelaunch() {
        let bundleURL = Bundle.main.bundleURL
        let destinationURL = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundleURL.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: bundleURL, to: destinationURL)

            try? FileManager.default.trashItem(at: bundleURL, resultingItemURL: nil)
            Logfile.app.info("[DirectoryCheck] Moved application to /Applications via FileManager. Restarting…")
            relaunchApp(from: destinationURL)
            return

        } catch {
            Logfile.app.warning(
                """
                [DirectoryCheck] FileManager move failed: \(error.localizedDescription), \
                falling back to privileged AppleScript
                """
            )
        }

        let sourcePath = bundleURL.path
        let destPath = "/Applications"
        let appName = bundleURL.lastPathComponent

        let scriptSource = """
        do shell script "rm -rf \\"\(destPath)/\(appName)\\" && \
        cp -R \\"\(sourcePath)\\" \\"\(destPath)/\\" && \
        rm -rf \\"\(sourcePath)\\"" with administrator privileges
        """

        var errorDict: NSDictionary?
        if let scriptObject = NSAppleScript(source: scriptSource) {
            _ = scriptObject.executeAndReturnError(&errorDict)

            if errorDict != nil {
                Logfile.app.error(
                    "[DirectoryCheck] AppleScript privileged move failed: \(String(describing: errorDict))"
                )
                let msg = """
                Could not move the application to /Applications automatically. Please move it manually to continue.
                """
                AlertShow.showInfo(
                    title: String(localized: "Failed to Move Application"),
                    message: String(localized: String.LocalizationValue(msg)),
                    style: .critical
                )
                NSApp.terminate(nil)
            } else {
                Logfile.app.info(
                    "[DirectoryCheck] Moved application to /Applications via AppleScript. Restarting…"
                )
                relaunchApp(from: destinationURL)
            }
        }
    }
}
