//
//  main.swift
//  AppLocker Launcher
//
//  Created by Doe Phương on 14/1/26.
//

import AppKit
import Foundation

// MARK: - Constants

let mainAppBundleID = "com.TranPhuong319.AppLocker"
let agentLabel = "com.TranPhuong319.AppLocker.agent"

// MARK: - Runtime checks

func isAgentRunning(label: String) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = ["print", "gui/\(getuid())/\(label)"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()  // Suppress error output

    do {
        try task.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        if let output = String(data: data, encoding: .utf8) {
            return output.contains("state = running")
        }
        return false
    } catch {
        return false
    }
}

// MARK: - Actions

func kickstartAgent(label: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = [
        "kickstart",
        "-k",
        "gui/\(getuid())/\(label)"
    ]
    try? task.run()
}

func launchMainAppSilently() {
    guard
        let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: mainAppBundleID
        )
    else {
        exit(1)
    }

    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    config.addsToRecentItems = false

    NSWorkspace.shared.openApplication(
        at: url,
        configuration: config
    )
}

// MARK: - Helper main logic

@MainActor
func helperMain() {

    // 1. Agent đang chạy → thoát
    if isAgentRunning(label: agentLabel) {
        exit(0)
    }

    // 2. Agent đã register nhưng chết → kickstart
    kickstartAgent(label: agentLabel)

    // 3. Nếu kickstart không tạo process → mở main app để nó register lại
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        if !isAgentRunning(label: agentLabel) {
            launchMainAppSilently()
        }
        exit(0)
    }
}

// MARK: - AppKit entry (no UI)

let app = NSApplication.shared

Task { @MainActor in
    helperMain()
}

app.run()
