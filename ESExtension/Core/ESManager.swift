//
//  ESManager.swift
//  AppLocker
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import EndpointSecurity
import os
import Darwin
import SystemConfiguration
import Combine

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
    var blockedSHAs: Set<String> = []              // Blocked SHA-256 digests.
    var blockedPathToSHA: [String: String] = [:]   // Path -> SHA cache map.

    // Temporary allow windows.
    var tempAllowedSHAs: [String: Date] = [:]     // SHA with expiry.
    let allowWindowSeconds: TimeInterval = 10     // Duration for one-time allow.

    // Allowed PIDs for config access.
    var allowedPIDs: [pid_t: Date] = [:]
    let allowedPIDWindowSeconds: TimeInterval = 5.0

    // Decision cache by path.
    var decisionCache: [String: ExecDecision] = [:]

    // Language settings for this process.
    var currentLanguage: String = Locale.preferredLanguages.first ?? "en"

    // MARK: - XPC connections / Kết nối XPC
    let xpcLock = FastLock()                        // Lock for connection list.
    var listener: NSXPCListener?                    // Mach service listener.
    var activeConnections: [NSXPCConnection] = []   // Active client connections.

    // Background queue for heavy I/O and hashing (not for locking state).
    let bgQueue = DispatchQueue(label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.bg", qos: .utility, attributes: .concurrent)

    var isReloadingConfig = false

    override init() {
        super.init()
        do {
            try ESManager.start(clientOwner: self)
        } catch {
            Logfile.es.error("ESManager failed start: \(error.localizedDescription, privacy: .public)")
        }
    }

    deinit {
        ESManager.stop(clientOwner: self)
    }

    // App -> Extension: grant short-lived access for a PID to read config.
    func allowConfigAccess(_ pid: Int32, withReply reply: @escaping (Bool) -> Void) {
        let pidAllow = pid_t(pid)
        let expiry = Date().addingTimeInterval(self.allowedPIDWindowSeconds)

        stateLock.perform {
            self.allowedPIDs[pidAllow] = expiry
        }

        Logfile.es.log(
            """
            allowConfigAccess granted for pid=\(pid, privacy: .public) \
            until \(expiry, privacy: .public)
            """
        )
        reply(true)
    }
}
