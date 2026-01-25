//
//  AppLockerHelper.swift
//  AppLockerHelper
//
//  Created by Doe Phương on 04/08/2025.
//

import Foundation
import OSLog
import ServiceManagement

class AppLockerHelper: NSObject, NSXPCListenerDelegate, AppLockerHelperProtocol {

    // MARK: - Auth State
    private static var authenticatedConnections: Set<ObjectIdentifier> = []
    private static let authLock = NSLock()

    private func isCurrentConnectionAuthenticated() -> Bool {
        guard let xpcConnection = NSXPCConnection.current() else { return false }
        var isAuthenticated = false
        AppLockerHelper.authLock.lock()
        isAuthenticated = AppLockerHelper.authenticatedConnections.contains(ObjectIdentifier(xpcConnection))
        AppLockerHelper.authLock.unlock()
        return isAuthenticated
    }

    // MARK: - Bundle ID Check (Ad-hoc Relaxed)
    private func verifyConnectionDetails() -> Bool {
        guard let xpcConnection = NSXPCConnection.current() else { return false }

        // Fallback: Use processIdentifier (PID) to get SecCode.
        // Note: PID is less secure than Audit Token (PID reuse), but acceptable here for Ad-hoc relaxed check.

        let logMessage = "Connection request from pid: \(xpcConnection.processIdentifier)"
        os_log("%{public}@", log: .default, type: .debug, logMessage)

        var secCode: SecCode?
        let processID = xpcConnection.processIdentifier
        let guestAttributesDictionary: [String: Any] = [kSecGuestAttributePid as String: Int(processID)]

        let status = SecCodeCopyGuestWithAttributes(nil, guestAttributesDictionary as CFDictionary, [], &secCode)

        guard status == errSecSuccess, let code = secCode else {
            os_log("Failed to get SecCode from PID", log: .default, type: .error)
            return false
        }

        // Convert SecCode -> SecStaticCode
        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(code, [], &staticCode)
        guard staticStatus == errSecSuccess, let staticCodeReference = staticCode else {
            os_log("Failed to get Static Code from SecCode", log: .default, type: .error)
            return false
        }

        // Get Info Dictionary to check Bundle ID
        var info: CFDictionary?
        // We use kSecCodeInfoSigningInformation to verify headers
        let infoStatus = SecCodeCopySigningInformation(staticCodeReference, [], &info)
        guard infoStatus == errSecSuccess, let signingInformationDictionary = info as? [String: Any] else {
             os_log("Failed to get signing info", log: .default, type: .error)
             return false
        }

        // Check Bundle ID (kSecCodeInfoIdentifier)
        if let bundleID = signingInformationDictionary[kSecCodeInfoIdentifier as String] as? String {
             os_log("Client Bundle ID: %{public}@", log: .default, type: .info, bundleID)

             let allowedIDs = [
                "com.TranPhuong319.AppLocker",
                "com.TranPhuong319.AppLocker.Launcher"
             ]

             if allowedIDs.contains(where: { bundleID == $0 || bundleID.hasPrefix($0) }) {
                 return true
             }
        }

        os_log("Client Bundle ID rejected", log: .default, type: .error)
        return false
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: AppLockerHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - AppLockerHelperProtocol Auth
    func authenticate(clientNonce: Data, clientSig: Data, clientPublicKey: Data, withReply reply: @escaping (Data?, Data?, Data?, Bool) -> Void) {
        guard let xpcConnection = NSXPCConnection.current() else {
            reply(nil, nil, nil, false)
            return
        }

        // 1. First, check Code Signing (Bundle ID)
        if !verifyConnectionDetails() {
            os_log("Auth: Bundle ID verification failed.", log: .default, type: .error)
            reply(nil, nil, nil, false)
            return
        }

        // 2. RSA Verification
        os_log("Auth: Verifying RSA signature...", log: .default, type: .info)

        // Import Client Public Key
        guard let clientKey = KeychainHelper.shared.createPublicKey(from: clientPublicKey) else {
            os_log("Auth: Failed to create client public key", log: .default, type: .error)
            reply(nil, nil, nil, false)
            return
        }

        // Verify Signature
        if !KeychainHelper.shared.verify(signature: clientSig, originalData: clientNonce, publicKey: clientKey) {
             os_log("Auth: RSA signature verification failed!", log: .default, type: .error)
             reply(nil, nil, nil, false)
             return
        }

        // 3. Generate Server Keys & Response
        let serverNonce = Data.random(count: 32)
        let combinedData = clientNonce + serverNonce
        let serverTag = KeychainHelper.Keys.helperPublic // Use Helper Key

        // Ensure Server Keys Exist
        if !KeychainHelper.shared.hasKey(tag: serverTag) {
            os_log("Auth: Generating new Helper keys...", log: .default, type: .info)
            try? KeychainHelper.shared.generateKeys(tag: serverTag)
        }

        // Sign Response
        guard let serverSig = KeychainHelper.shared.sign(data: combinedData, tag: serverTag) else {
            os_log("Auth: Failed to sign server response", log: .default, type: .error)
            reply(nil, nil, nil, false)
            return
        }

        // Export Server Public Key
        guard let serverPubKeyData = KeychainHelper.shared.exportPublicKey(tag: serverTag) else {
             os_log("Auth: Failed to export server public key", log: .default, type: .error)
             reply(nil, nil, nil, false)
             return
        }

        // 4. Mark Authenticated
        AppLockerHelper.authLock.lock()
        AppLockerHelper.authenticatedConnections.insert(ObjectIdentifier(xpcConnection))
        AppLockerHelper.authLock.unlock()

        xpcConnection.invalidationHandler = {
            AppLockerHelper.authLock.lock()
            AppLockerHelper.authenticatedConnections.remove(ObjectIdentifier(xpcConnection))
            AppLockerHelper.authLock.unlock()
        }

         os_log("Auth: Successful!", log: .default, type: .info)
        reply(serverNonce, serverSig, serverPubKeyData, true)
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
            reply(false, "Command not supported: \(command)")
            return
        }

        process.arguments = args

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                reply(true, output.isEmpty ? "\(command) success" : output)
            } else {
                reply(false, error.isEmpty ? "\(command) failure" : error)
            }
        } catch {
            reply(false, "Can't run \(command): \(error.localizedDescription)")
        }
    }

    // MARK: - Parse args safely
    private func parseArgs(_ object: Any?) -> [String]? {
        guard let argumentsList = object as? [Any] else { return nil }
        return argumentsList.map { "\($0)" } // convert mọi thứ sang string
    }

    // MARK: - Batch with rollback
    func sendBatch(_ commands: [[String: Any]], withReply reply: @escaping (Bool, String) -> Void) {
        // Enforce Authentication
        guard isCurrentConnectionAuthenticated() else {
             os_log("Access Denied: Connection not authenticated.", log: .default, type: .error)
             reply(false, "Access Denied: Unauthorized client.")
             return
        }

        var messages: [String] = []

        for (index, cmdPair) in commands.enumerated() {
            // Parse DO
            guard let doCmd = cmdPair["do"] as? [String: Any],
                  let command = doCmd["command"] as? String,
                  let argumentsList = parseArgs(doCmd["args"]) else {
                messages.append("Invalid 'do' command at index \(index)")
                reply(false, messages.joined(separator: "\n"))
                return
            }

            // Run DO
            let stepSemaphore = DispatchSemaphore(value: 0)
            var isDoSuccess = false
            var stepOutputMessage = ""
            sendCommand(command, args: argumentsList) { isSuccess, output in
                isDoSuccess = isSuccess
                stepOutputMessage = output
                stepSemaphore.signal()
            }
            stepSemaphore.wait()
            messages.append("Step \(index) do: \(stepOutputMessage)")

            // Nếu fail → chạy UNDO của chính lệnh đó
            if !isDoSuccess, let undoCmd = cmdPair["undo"] as? [String: Any],
               let undoCommand = undoCmd["command"] as? String,
               let undoArguments = parseArgs(undoCmd["args"]) {
                messages.append("Step \(index) FAILED, running UNDO...")
                let undoStepSemaphore = DispatchSemaphore(value: 0)
                sendCommand(undoCommand, args: undoArguments) { isUndoSuccess, output in
                    messages.append(isUndoSuccess ? "UNDO OK: \(output)" : "UNDO FAIL: \(output)")
                    undoStepSemaphore.signal()
                }
                undoStepSemaphore.wait()
                reply(false, messages.joined(separator: "\n"))
                return
            } else if !isDoSuccess {
                messages.append("Step \(index) FAILED, no UNDO available")
                reply(false, messages.joined(separator: "\n"))
                return
            }
        }

        // Nếu tất cả DO thành công
        reply(true, messages.joined(separator: "\n"))
    }

    func uninstallHelper(withReply reply: @escaping (Bool, String) -> Void) {
        // Enforce Auth
        guard isCurrentConnectionAuthenticated() else {
             reply(false, "Access Denied: Unauthorized client.")
             return
        }

        var logs: [String] = []

        func run(_ cmd: String, args: [String]) -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cmd)
            process.arguments = args

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8) ?? ""
                logs.append("\(cmd) \(args.joined(separator: " "))\n\(out)")
                return process.terminationStatus == 0
            } catch {
                logs.append("Error: \(error.localizedDescription)")
                return false
            }
        }

        _ = run("/bin/launchctl", args: ["bootout", "system/com.TranPhuong319.AppLocker.Helper"])

        _ = run("/bin/launchctl", args: ["disable", "system/com.TranPhuong319.AppLocker.Helper"])

        _ = run("/bin/rm", args: ["-rf", "~/Library/Application Support/AppLocker"])

        _ = run("/bin/rm", args: ["-rf", "~/Library/Preferences/com.TranPhuong319.AppLocker.plist"])

        _ = run("/bin/rm", args: ["-rf", "/Applications/AppLocker.app"])

        _ = run("/usr/bin/killall", args: ["com.TranPhuong319.AppLocker.Helper"])

        reply(true, logs.joined(separator: "\n"))
    }
}

extension Data {
    static func random(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        return data
    }
}
