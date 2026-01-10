//
//  ESManager.swift
//  AppLocker
//
//  Created by Doe Phương on 29/12/25.
//

import Combine
import Darwin
import EndpointSecurity
import Foundation
import SystemConfiguration
import os

@objcMembers
final class ESManager: NSObject {
    // Static trampoline for C-style ES callbacks.
    static var sharedInstanceForCallbacks: ESManager?

    // Published state for host app UI.
    @Published var lockedApps: [String: LockedAppConfig] = [:]

    // Endpoint Security client handle (managed in EndpointSecurity/ESClient.swift).
    var client: OpaquePointer?

    // MARK: - State / Trạng thái
    // Ultra-fast in-memory policy/state protected by a single lock.
    let stateLock = FastLock()

    // Block lists / mappings.
    var blockedSHAs: Set<String> = []  // Blocked SHA-256 digests.
    var blockedPathToSHA: [String: String] = [:]  // Path -> SHA cache map.

    // Temporary allow windows.
    var tempAllowedSHAs: [String: Date] = [:]  // SHA with expiry.
    let allowWindowSeconds: TimeInterval = 10  // Duration for one-time allow.

    // Allowed PIDs for config access.
    let allowedPIDWindowSeconds: TimeInterval = 5.0

    // Decision cache by path.
    var decisionCache: [String: ExecDecision] = [:]

    // Language settings for this process.
    var currentLanguage: String = Locale.preferredLanguages.first ?? "en"

    // MARK: - XPC connections / Kết nối XPC
    let xpcLock = FastLock()  // Lock for connection list.
    var listener: NSXPCListener?  // Mach service listener.
    var activeConnections: [NSXPCConnection] = []  // Active client connections.
    var authenticatedConnections: Set<ObjectIdentifier> = []  // Authenticated connections.

    // Check if current connection is authenticated
    func isCurrentConnectionAuthenticated() -> Bool {
        guard let conn = NSXPCConnection.current() else { return false }
        return xpcLock.sync { authenticatedConnections.contains(ObjectIdentifier(conn)) }
    }

    // Background queue for heavy I/O and hashing (not for locking state).
    let bgQueue = DispatchQueue(
        label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.bg", qos: .utility,
        attributes: .concurrent)
    let allowedPIDsQueue = DispatchQueue(
        label: "com.TranPhuong319.AppLocker.allowedPIDs", attributes: .concurrent)
    var _allowedPIDs: [pid_t: Date] = [:]

    // Dùng accessor để truy xuất thread-safe
    var allowedPIDs: [pid_t: Date] {
        get { allowedPIDsQueue.sync { _allowedPIDs } }
        set { allowedPIDsQueue.async(flags: .barrier) { self._allowedPIDs = newValue } }
    }

    override init() {
        super.init()
        // Ensure "Shared" keychain access
        if #available(macOS 12.0, *) {
            // Just logging for verification
            Logfile.es.log("ESManager initialized. Ready for XPC.")
        }
        do {
            try ESManager.start(clientOwner: self)
        } catch {
            Logfile.es.error(
                "ESManager failed start: \(error.localizedDescription, privacy: .public)")
        }
    }

    deinit {
        ESManager.stop(clientOwner: self)
    }

    // App -> Extension: grant short-lived access for a PID to read config.
    func allowConfigAccess(_ pid: Int32, withReply reply: @escaping (Bool) -> Void) {
        guard isCurrentConnectionAuthenticated() else {
            Logfile.es.error("Unauthorized call to allowConfigAccess")
            reply(false)
            return
        }
        let pidAllow = pid_t(pid)
        let now = Date()
        let expiry = now.addingTimeInterval(self.allowedPIDWindowSeconds)

        // Dọn dẹp nếu size > threshold
        allowedPIDsQueue.async(flags: .barrier) {
            if self._allowedPIDs.count > 10 {
                self._allowedPIDs = self._allowedPIDs.filter { $0.value > now }
            }
            self._allowedPIDs[pidAllow] = expiry
        }

        Logfile.es.log("allowConfigAccess granted for pid=\(pid) until \(expiry)")
        reply(true)
    }
}
