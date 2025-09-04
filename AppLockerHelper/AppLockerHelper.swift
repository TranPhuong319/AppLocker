//
//  AppLockerHelper.swift
//  AppLockerHelper
//
//  Created by Doe Phương on 04/08/2025.
//

import Foundation
import OSLog

class AppLockerHelper: NSObject, NSXPCListenerDelegate, AppLockerHelperProtocol {
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: AppLockerHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - Run a single command
    func sendCommand(_ command: String, args: [String], withReply reply: @escaping (Bool, String) -> Void) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        switch command {
        case "mkdir":       process.executableURL = URL(fileURLWithPath: "/bin/mkdir")
        case "cp":          process.executableURL = URL(fileURLWithPath: "/bin/cp")
        case "rm":          process.executableURL = URL(fileURLWithPath: "/bin/rm")
        case "mv":          process.executableURL = URL(fileURLWithPath: "/bin/mv")
        case "chmod":       process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        case "chflags":     process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        case "chown":       process.executableURL = URL(fileURLWithPath: "/usr/sbin/chown")
        case "PlistBuddy":  process.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
        case "touch":       process.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
        default:
            reply(false, "❌ Command not supported: \(command)")
            return
        }
        
        process.arguments = args
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 {
                reply(true, output.isEmpty ? "✅ \(command) success\n" : output)
            } else {
                reply(false, error.isEmpty ? "❌ \(command) failure\n" : error)
            }
        } catch {
            reply(false, "❌ Can't run \(command): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Parse args safely
    private func parseArgs(_ obj: Any?) -> [String]? {
        guard let arr = obj as? [Any] else { return nil }
        return arr.map { "\($0)" } // convert mọi thứ sang string
    }
    
    // MARK: - Batch with rollback
    func sendBatch(_ commands: [[String: Any]], withReply reply: @escaping (Bool, String) -> Void) {
        var messages: [String] = []
        
        for (index, cmdPair) in commands.enumerated() {
            // Parse DO
            guard let doCmd = cmdPair["do"] as? [String: Any],
                  let command = doCmd["command"] as? String,
                  let args = parseArgs(doCmd["args"]) else {
                messages.append("❌ Invalid 'do' command at index \(index)")
                reply(false, messages.joined(separator: "\n"))
                return
            }
            
            // Run DO
            let sem = DispatchSemaphore(value: 0)
            var doSuccess = false
            var outputMsg = ""
            sendCommand(command, args: args) { ok, out in
                doSuccess = ok
                outputMsg = out
                sem.signal()
            }
            sem.wait()
            messages.append("Step \(index) do: \(outputMsg)")
            
            // Nếu fail → chạy UNDO của chính lệnh đó
            if !doSuccess, let undoCmd = cmdPair["undo"] as? [String: Any],
               let undoCommand = undoCmd["command"] as? String,
               let undoArgs = parseArgs(undoCmd["args"]) {
                messages.append("⚠️ Step \(index) FAILED, running UNDO...")
                let undoSem = DispatchSemaphore(value: 0)
                sendCommand(undoCommand, args: undoArgs) { ok, out in
                    messages.append(ok ? "↩️ UNDO OK: \(out)" : "❌ UNDO FAIL: \(out)")
                    undoSem.signal()
                }
                undoSem.wait()
                reply(false, messages.joined(separator: "\n"))
                return
            } else if !doSuccess {
                messages.append("❌ Step \(index) FAILED, no UNDO available")
                reply(false, messages.joined(separator: "\n"))
                return
            }
        }
        
        // Nếu tất cả DO thành công
        reply(true, messages.joined(separator: "\n"))
    }
}
