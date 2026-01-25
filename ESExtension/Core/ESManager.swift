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

    // Legacy support for other parts of the code
    var authClient: OpaquePointer? { authorizer?.client }
    var fileClient: OpaquePointer? { tamper?.client }

    // MARK: - State
    let stateLock = FastLock()
    var blockedSHAs: Set<String> = []
    var blockedPathToSHA: [String: String] = [:]
    var tempAllowedSHAs: [String: Date] = [:]
    let allowWindowSeconds: TimeInterval = 10
    var decisionCache: [String: ExecDecision] = [:]
    var currentLanguage: String = Locale.preferredLanguages.first ?? "en"

    // MARK: - Locks and Queues
    let xpcConnectionLock = FastLock()
    var listener: NSXPCListener?
    var activeConnections: [NSXPCConnection] = []
    var authenticatedConnections: Set<ObjectIdentifier> = []
    var authenticatedMainAppPID: pid_t?
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
    let MaxInFlightMessages: Int32 = 100
    let shaSemaphore = DispatchSemaphore(value: 12)

    // Key generation lock to prevent concurrent RSA generation spikes
    private let keyGenLock = os_unfair_lock()

    // MARK: - File Access Cache / Rate Limiting (Flood Protection)
    let fileAccessLock = FastLock()
    /// Cache kết quả allow nhanh cho path, tránh check lại logic phức tạp
    var fileAccessAllowCache: Set<String> = []
    /// Track lần truy cập cuối cùng cho mỗi path để rate limit (Fail-Open)
    var recentFileAccess: [String: [Date]] = [:]

    override init() {
        super.init()
        Logfile.es.pLog("ESManager initializing...")

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
            Logfile.es.pLog("Modular ES Clients created and self-muted.")

            // 3. Async Key Generation (Optimized EC P-256)
            // Move off main thread to prevent init blocking, but guard via Group
            keyGenGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.prepareAuthenticationKeys()
                self?.keyGenGroup.leave()
            }
            
            scheduleTempCleanup()

            // 4. Setup Listener (Ready for connections)
            setupMachListener()

            // 5. Enable (Subscribe)
            // Now safe to receive events
            authorizer.enable()
            tamper.enable()

            Logfile.es.pLog("Modular ES Clients enabled and active.")
            
        } else {
            Logfile.es.pError("Failed to start modular ES Clients.")
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

    func invalidateCache(forPath path: String) {
        stateLock.perform {
            decisionCache.removeValue(forKey: path)
            blockedPathToSHA.removeValue(forKey: path)
        }
        Logfile.es.pLog("Cache invalidated for: \(path)")
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
        Logfile.es.pLog("Handshake/ConfigAccess requested (Muted via AuditToken) for pid=\(processID)")
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
        // Critical: Mute AppLocker immediately to prevent deadlock on Config IO
        muteAppLockerProcess(&auditToken)
    }

    // MARK: - Muting Logic

    private func muteSelf() {
        guard let client = authorizer?.client else { return }
        if let token = getMyAuditToken() {
             var mutableToken = token
             if es_mute_process(client, &mutableToken) == ES_RETURN_SUCCESS {
                 Logfile.es.pLog("Mute self result: Success")
             } else {
                 Logfile.es.pError("Mute self result: Failed")
             }
        }
    }

    func muteAppLockerProcess(_ token: UnsafePointer<audit_token_t>) {
        guard let client = authorizer?.client else { return }
        
        // Mute for Authorizer
        if es_mute_process(client, token) == ES_RETURN_SUCCESS {
            Logfile.es.pLog("Muted AppLocker PID (Authorizer): Success")
        } else {
            Logfile.es.pError("Mute AppLocker PID (Authorizer): Failed")
        }
        
        // Mute for Tamper too if needed (though Tamper usually monitors only config writes)
        if let tamperClient = tamper?.client {
            if es_mute_process(tamperClient, token) == ES_RETURN_SUCCESS {
                Logfile.es.pLog("Muted AppLocker PID (Tamper): Success")
            }
        }
    }

    private func getMyAuditToken() -> audit_token_t? {
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
            Logfile.es.pLog("Auth: Pre-generating server keys at startup...")
            let startTime = mach_absolute_time()

            do {
                try KeychainHelper.shared.generateKeys(tag: serverTag)

                var timebaseInfo = mach_timebase_info_data_t()
                mach_timebase_info(&timebaseInfo)
                let elapsed =
                    Double(mach_absolute_time() - startTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
                    / 1_000_000.0

                Logfile.es.pLog("Auth: Keys generated in \(String(format: "%.1f", elapsed))ms")
            } catch {
                Logfile.es.pError("Auth: Pre-generation failed: \(error)")
            }
        } else {
            Logfile.es.pLog("Auth: Server keys already exist")
        }
    }

    func clearMainAppPID() { processIDLock.perform { self.authenticatedMainAppPID = nil } }

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
