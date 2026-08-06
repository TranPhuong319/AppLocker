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
    static var sharedInstanceForCallbacks: ESManager?
    var authorizer: ESAuthorizer?
    var tamper: ESTamper?

    // MARK: - State
    let stateLock = FastLock()
    var lockedCDHashes: [uid_t: Set<String>] = [:]
    var lockedBundlePaths: [uid_t: Set<String>] = [:]
    var currentLanguage: String = Locale.preferredLanguages.first ?? "en"
    var configMonitorSource: DispatchSourceFileSystemObject?

    struct BlockedNotification {
        let name: String
        let path: String
        let cdhash: String
        let parentPid: pid_t
        let uid: uid_t
        let signingID: String
        let targetPid: pid_t
    }

    var pendingNotifications: [BlockedNotification] = []
    let pendingPIDLock = FastLock()
    var pendingVerificationPIDs: Set<pid_t> = []

    // MARK: - Locks and Queues
    let xpcConnectionLock = FastLock()
    var listener: NSXPCListener?
    var activeConnections: [NSXPCConnection] = []
    var authenticatedConnections: Set<ObjectIdentifier> = []
    var authenticatedMainAppPID: pid_t?
    var activeUserUID: uid_t?
    var isShutdownAuthorized: Bool = false
    let processIDLock = FastLock()
    let backgroundProcessingQueue = DispatchQueue(
        label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.bg", qos: .userInitiated,
        attributes: .concurrent)

    /// Queue chuyên dụng cho xử lý AUTH events (CONCURRENT cho burst throughput)
    let authorizationProcessingQueue = DispatchQueue(
        label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.auth",
        qos: .userInteractive,
        attributes: .concurrent)

    /// Queue riêng cho emergency timer (serial, high priority) - KHÔNG BAO GIỜ bị block
    let emergencyTimerQueue = DispatchQueue(
        label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.emergency",
        qos: .userInteractive)

    /// Group to coordinate Async Key Generation
    let keyGenGroup = DispatchGroup()

    var activeMessageCount: Int32 = 0

    override init() {
        super.init()
        Logfile.endpointSecurity.log("ESManager initializing...")

        ESManager.sharedInstanceForCallbacks = self

        // 1. Setup Clients
        let authorizer = ESAuthorizer()
        let tamper = ESTamper()

        authorizer.manager = self
        tamper.manager = self

        self.authorizer = authorizer
        self.tamper = tamper

        // 2. Start Clients (Calls createClient -> MuteSelf internally)
        if authorizer.start() && tamper.start() {
            Logfile.endpointSecurity.log("Modular ES Clients created and self-muted.")

            // 3. Async Key Generation (Optimized EC P-256)
            // Move off main thread to prevent init blocking, but guard via Group
            keyGenGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.prepareAuthenticationKeys()
                self?.keyGenGroup.leave()
            }

            // 4. Setup Listener (Ready for connections)
            setupMachListener()

            // 5. Initial Config & Monitoring
            loadInitialConfigSync()
            startConfigMonitoring()

            // 6. Enable (Subscribe)
            // Now safe to receive events
            authorizer.enable()
            tamper.enable()

            Logfile.endpointSecurity.log("Modular ES Clients enabled and active.")

        } else {
            Logfile.endpointSecurity.error("Failed to start modular ES Clients.")
        }
    }

    deinit {
        authorizer = nil
        tamper = nil
        // SURGICAL: Only clear singleton if it's still us.
        // This prevents a new instance's pointer from being cleared by an old instance's deinit.
        if ESManager.sharedInstanceForCallbacks === self {
            ESManager.sharedInstanceForCallbacks = nil
        }
    }

    func isCurrentConnectionAuthenticated() -> Bool {
        guard let connection = NSXPCConnection.current() else { return false }
        return xpcConnectionLock.sync { authenticatedConnections.contains(ObjectIdentifier(connection)) }
    }

    func allowConfigAccess(
        _ processID: Int32,
        withReply reply: @escaping (Bool) -> Void
    ) {
        // Handshake only. Muting handled by cacheMainAppPID on connection accept.
        guard isCurrentConnectionAuthenticated() else {
            reply(false)
            return
        }
        Logfile.endpointSecurity.log("Handshake/ConfigAccess requested (Muted via AuditToken) for pid=\(processID)")
        reply(true)
    }

    func authorizeShutdown(_ authorized: Bool, withReply reply: @escaping (Bool) -> Void) {
        guard isCurrentConnectionAuthenticated() else {
            reply(false)
            return
        }
        stateLock.perform {
            self.isShutdownAuthorized = authorized
        }
        Logfile.endpointSecurity.log("Authorized shutdown status updated to: \(authorized)")
        reply(true)
    }

    func isMainAppProcess(_ process: UnsafePointer<es_process_t>) -> Bool {
        let processPid = audit_token_to_pid(process.pointee.audit_token)
        return processIDLock.sync { processPid == authenticatedMainAppPID }
    }

    func cacheMainAppPID(from connection: NSXPCConnection) {
        let processID = connection.processIdentifier
        processIDLock.perform { self.authenticatedMainAppPID = pid_t(processID) }

        var auditToken = connection.esAuditToken
        stateLock.perform {
            self.activeUserUID = audit_token_to_euid(auditToken)
        }

        // Critical: Mute AppLocker immediately to prevent deadlock on Config IO
        muteAppLockerProcess(&auditToken)
    }

    func incrementActiveMessageCount() {
        stateLock.perform { activeMessageCount += 1 }
    }

    func decrementActiveMessageCount() {
        stateLock.perform { activeMessageCount -= 1 }
    }

    // MARK: - Muting Logic

    func muteAppLockerProcess(_ token: UnsafePointer<audit_token_t>) {
        guard let client = authorizer?.client else { return }

        // Mute for Authorizer
        if es_mute_process(client, token) == ES_RETURN_SUCCESS {
            Logfile.endpointSecurity.log("Muted AppLocker PID (Authorizer): Success")
        } else {
            Logfile.endpointSecurity.error("Mute AppLocker PID (Authorizer): Failed")
        }

        // Mute for Tamper too if needed (though Tamper usually monitors only config writes)
        if let tamperClient = tamper?.client {
            if es_mute_process(tamperClient, token) == ES_RETURN_SUCCESS {
                Logfile.endpointSecurity.log("Muted AppLocker PID (Tamper): Success")
            }
        }
    }

    static func getSelfAuditToken() -> audit_token_t? {
        var token = audit_token_t()
        var size = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size)

        let kernResult = withUnsafeMutablePointer(to: &token) { tokenPtr in
            tokenPtr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_AUDIT_TOKEN), intPtr, &size)
            }
        }

        if kernResult == KERN_SUCCESS {
            return token
        }
        return nil
    }

    func prepareAuthenticationKeys() {
        let serverTag = KeychainHelper.Keys.extensionPublic

        if !KeychainHelper.shared.hasKey(tag: serverTag) {
            Logfile.endpointSecurity.log("Auth: Pre-generating server keys at startup...")
            let startTime = mach_absolute_time()

            do {
                try KeychainHelper.shared.generateKeys(tag: serverTag)

                let elapsedNanos = ESManager.machTimeToNanos(mach_absolute_time() - startTime)
                let elapsedMs = Double(elapsedNanos) / 1_000_000.0

                Logfile.endpointSecurity.log("Auth: Keys generated in \(String(format: "%.1f", elapsedMs))ms")
            } catch {
                Logfile.endpointSecurity.error("Auth: Pre-generation failed: \(error)")
            }
        } else {
            Logfile.endpointSecurity.log("Auth: Server keys already exist")
        }
    }

    // MARK: - Time Utilities
    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func machTimeToNanos(_ machTime: UInt64) -> UInt64 {
        return machTime * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
    }
}

extension NSXPCConnection {
    var esAuditToken: audit_token_t {
        var token = audit_token_t()
        if let value = self.value(forKey: "auditToken") as? NSValue { value.getValue(&token) }
        return token
    }
}
