//
//  AppLockerHelper.swift
//  AppLockerHelper
//
//  Created by Doe Phương on 04/08/2025.
//

import Foundation
import OSLog

class AppLockerHelper:  NSObject, NSXPCListenerDelegate, AppLockerHelperProtocol {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: AppLockerHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }
    
    func sendCommand(_ command: String, args: [String], withReply reply: @escaping (Bool, String) -> Void) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        switch command {
        case "mkdir":
            process.executableURL = URL(fileURLWithPath: "/bin/mkdir")
            process.arguments = args
            
        case "cp":
            process.executableURL = URL(fileURLWithPath: "/bin/cp")
            process.arguments = args

        case "rm":
            process.executableURL = URL(fileURLWithPath: "/bin/rm")
            process.arguments = args

        case "mv":
            process.executableURL = URL(fileURLWithPath: "/bin/mv")
            process.arguments = args

        case "chmod":
            process.executableURL = URL(fileURLWithPath: "/bin/chmod")
            process.arguments = args

        case "chflags":
            process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
            process.arguments = args

        case "chown":
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/chown")
            process.arguments = args
        case "PlistBuddy":
            process.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
            process.arguments = args
        case "touch":
            process.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
            process.arguments = args

        default:
            reply(false, "❌ Command is not supported: \(command)")
            return
        }

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                reply(true, output.isEmpty ? "✅ \(command) OK" : output)
            } else {
                reply(false, error.isEmpty ? "❌ \(command) failure" : error)
            }
        } catch {
            reply(false, "❌ Can't run commands \(command): \(error.localizedDescription)")
        }
    }

    func sendBatch(_ commands: [[String: Any]], withReply reply: @escaping (Bool, String) -> Void) {
        var allSuccess = true
        var messages: [String] = []

        for cmd in commands {
            guard let command = cmd["command"] as? String,
                  let args = cmd["args"] as? [String] else {
                messages.append("❌ Invalid command: \(cmd)")
                allSuccess = false
                continue
            }

            // Gọi lại hàm đã viết sẵn (reused logic)
            let semaphore = DispatchSemaphore(value: 0)
            sendCommand(command, args: args) { success, msg in
                if !success { allSuccess = false }
                messages.append(msg)
                semaphore.signal()
            }
            semaphore.wait()
        }

        reply(allSuccess, messages.joined(separator: "\n"))
    }
}
