//
//  AppLauncherUtils.swift
//  ESExtension
//
//  Created by Antigravity on 07/02/26.
//

import Foundation
import os

struct AppLauncherUtils {
    static let agentLabel = "com.TranPhuong319.AppLocker.agent"
    
    /// Đánh thức App chính (dưới dạng LaunchAgent) cho một User ID cụ thể
    /// Lệnh: launchctl asuser <uid> launchctl kickstart -p gui/<uid>/<label>
    static func wakeUpMainApp(for uid: uid_t) {
        let uidString = String(uid)
        let serviceTarget = "gui/\(uidString)/\(agentLabel)"
        
        let path = "/bin/launchctl"
        let args = ["asuser", uidString, "launchctl", "kickstart", "-p", serviceTarget]
        
        Logfile.endpointSecurity.log("Auto-Wake: Attempting to wake up agent for UID \(uidString)...")
        
        executeCommand(path: path, args: args)
    }
    
    private static func executeCommand(path: String, args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        
        // Cần thiết lập pipe để tránh treo nếu output quá lớn, mặc dù lệnh này output ít
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Logfile.endpointSecurity.log("Auto-Wake output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            
            if task.terminationStatus == 0 {
                Logfile.endpointSecurity.log("Auto-Wake: Command executed successfully.")
            } else {
                Logfile.endpointSecurity.error("Auto-Wake: Command failed with status \(task.terminationStatus)")
            }
        } catch {
            Logfile.endpointSecurity.error("Auto-Wake: Failed to run process: \(error.localizedDescription)")
        }
    }
    
    static func forceEnableAndRestartAgent(for uid: uid_t) {
        let uidStr = String(uid)
        
        Logfile.endpointSecurity.log("Guardian: Forcing enable and kickstart for \(agentLabel) (UID: \(uidStr))")
        
        // 1. Force enable (overrides System Settings Off state)
        let enableArgs = ["asuser", uidStr, "launchctl", "enable", "gui/\(uidStr)/\(agentLabel)"]
        executeCommand(path: "/bin/launchctl", args: enableArgs)
        
        // 2. Kickstart (ensures it's running)
        let kickstartArgs = ["asuser", uidStr, "launchctl", "kickstart", "-p", "gui/\(uidStr)/\(agentLabel)"]
        executeCommand(path: "/bin/launchctl", args: kickstartArgs)
    }
}
