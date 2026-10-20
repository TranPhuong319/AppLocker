//
//  AppLauncherUtils.swift
//  ESExtension
//
//  Created by Doe Phương on 7/2/26.
//

import Foundation
import os

struct AppLauncherUtils {
    static let agentLabel = "com.TranPhuong319.AppLocker.agent"

    private static func executeCommand(path: String, args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args

        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                Logfile.endpointSecurity.debug("[AutoWake] Command executed successfully.")
            } else {
                Logfile.endpointSecurity.error(
                    "[AutoWake] Command failed with status \(task.terminationStatus, privacy: .public)"
                )
            }
        } catch {
            Logfile.endpointSecurity.error("[AutoWake] Failed to run process: \(error.localizedDescription)")
        }
    }

    static func forceEnableAndRestartAgent(for uid: uid_t) {
        let uidStr = String(uid)

        Logfile.endpointSecurity.info(
            """
            [Guardian] Forcing enable and kickstart for \(agentLabel, privacy: .public) \
            (UID: \(uidStr, privacy: .public))
            """
        )

        // 1. Force enable (overrides System Settings Off state)
        let enableArgs = ["asuser", uidStr, "launchctl", "enable", "gui/\(uidStr)/\(agentLabel)"]
        executeCommand(path: "/bin/launchctl", args: enableArgs)

        // 2. Kickstart (ensures it's running)
        let kickstartArgs = ["asuser", uidStr, "launchctl", "kickstart", "-p", "gui/\(uidStr)/\(agentLabel)"]
        executeCommand(path: "/bin/launchctl", args: kickstartArgs)
    }
}
