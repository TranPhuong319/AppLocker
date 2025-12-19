//
//  ESManager.swift
//  AppLocker
//
//  Created by Doe Phương on 26/9/25.
//

import Foundation
import EndpointSecurity
import os
import Darwin
import SystemConfiguration
import Combine
import CryptoKit

enum ExecDecision {
    case allow
    case deny
}

@objcMembers
final class ESManager: NSObject, NSXPCListenerDelegate {
    static var sharedInstanceForCallbacks: ESManager?

    // Public observable for the host app
    @Published var lockedApps: [String: LockedAppConfig] = [:]

    // ES client
    private var client: OpaquePointer?

    // Block lists / mappings (guarded by stateQueue)
    // blockedSHAs: authoritative set of blocked SHA256 strings
    private var blockedSHAs: Set<String> = []
    // blockedPathToSHA: map executable path -> known sha (populated from config or computed async)
    private var blockedPathToSHA: [String: String] = [:]
    fileprivate let stateQueue = DispatchQueue(label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.state")

    // Temporary allow windows (SHA -> expiry)
    private var tempAllowedSHAs: [String: Date] = [:]
    private let tempQueue = DispatchQueue(label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.temp")
    private let allowWindowSeconds: TimeInterval = 10

    // Allowed PIDs for config access
    private var allowedPIDs: [pid_t: Date] = [:]
    private let allowedPIDsQueue = DispatchQueue(label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.allowedPIDs")
    private let allowedPIDWindowSeconds: TimeInterval = 5.0

    // Decision cache for quick lookups by path (path -> ExecDecision)
    private var decisionCache: [String: ExecDecision] = [:]
    private let decisionQueue = DispatchQueue(label: "es.decision.cache")

    // Watchers for config file(s)
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private let watchersQueue = DispatchQueue(label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.watchers")

    private lazy var candidateConfigURLs: [URL] = {
        var urls: [URL] = []
        if let home = consoleUserHomeDirectory() {
            let userAppSupport = URL(fileURLWithPath: home)
                .appendingPathComponent("Library/Application Support/AppLocker/config.plist")
            urls.append(userAppSupport)
        }
        return urls
    }()

    // Mach Service listener & incoming connections
    private var listener: NSXPCListener?
    private var activeConnections: [NSXPCConnection] = []
    private let activeConnectionsQueue = DispatchQueue(label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc.conns")

    private var isReloadingConfig = false

    override init() {
        super.init()
        do {
            try start()
        } catch {
            Logfile.es.error("ESManager failed start: \(error.localizedDescription, privacy: .public)")
        }
    }

    deinit { stop() }

    private func consoleUserHomeDirectory() -> String? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        if let cfName = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) {
            let username = cfName as String
            if username == "loginwindow" { return nil }
            let homePtr = username.withCString { cstr -> UnsafeMutablePointer<passwd>? in
                return getpwnam(cstr)
            }
            if let pw = homePtr {
                return String(cString: pw.pointee.pw_dir)
            } else {
                return "/Users/\(username)"
            }
        }
        return nil
    }

    // App -> Extension: request access for config
    @objc func allowConfigAccess(_ pid: Int32, withReply reply: @escaping (Bool) -> Void) {
        let p = pid_t(pid)
        allowedPIDsQueue.async { [weak self] in
            guard let self = self else { reply(false); return }
            let expiry = Date().addingTimeInterval(self.allowedPIDWindowSeconds)
            self.allowedPIDs[p] = expiry
            Logfile.es.log("allowConfigAccess granted for pid=\(p, privacy: .public) until \(expiry, privacy: .public)")
            reply(true)
        }
    }

    private func scheduleTempCleanup() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.cleanupTempAllowed()
            self?.scheduleTempCleanup()
        }
    }

    private func cleanupTempAllowed() {
        tempQueue.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            var removedSHAs: [String] = []
            for (sha, expiry) in self.tempAllowedSHAs where expiry <= now {
                self.tempAllowedSHAs.removeValue(forKey: sha)
                removedSHAs.append(sha)
            }
            if !removedSHAs.isEmpty { Logfile.es.log("Temp allowed SHAs expired: \(removedSHAs.count, privacy: .public)") }
        }
    }

    private func isTempAllowed(_ sha: String) -> Bool {
        return tempQueue.sync {
            if let expiry = tempAllowedSHAs[sha], expiry > Date() { return true }
            return false
        }
    }

    private static func safePath(fromFilePointer filePtr: UnsafePointer<es_file_t>?) -> String? {
        guard let filePtr = filePtr else { return nil }
        let file = filePtr.pointee
        if let cstr = file.path.data {
            return String(cString: cstr)
        }
        // If above not valid, attempt use other es APIs or return nil
        return nil
    }
}

// MARK: - Helper: respond with safe delay within ES deadline
@inline(__always)
func respondWithDeadline(
    _ result: es_auth_result_t,
    client: OpaquePointer,
    message: UnsafePointer<es_message_t>,
    desiredDelayNs: UInt64 = 5_000_000 // 5ms
) {
    let now = mach_absolute_time()
    let deadline = message.pointee.deadline

    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)

    @inline(__always)
    func machToNanos(_ t: UInt64) -> UInt64 {
        t * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    let remainingNs = machToNanos(deadline > now ? deadline - now : 0)
    let marginNs: UInt64 = 500_000 // 0.5ms safety
    let safeDelayNs = min(desiredDelayNs, remainingNs > marginNs ? remainingNs - marginNs : 0)

    if safeDelayNs > 0 {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + .nanoseconds(Int(safeDelayNs))
        ) {
            es_respond_auth_result(client, message, result, false)
        }
    } else {
        es_respond_auth_result(client, message, result, false)
    }
}

// MARK: - Lifecycle setup
extension ESManager {
    private func start() throws {
        setupMachListener()

        let res = es_new_client(&self.client) { client, message in
            ESManager.handleMessage(client: client, message: message)
        }

        guard res == ES_NEW_CLIENT_RESULT_SUCCESS, let client = self.client else {
            Logfile.es.error("es_new_client failed: \(String(describing: res), privacy: .public)")
            throw NSError(domain: "ESManager", code: 1, userInfo: nil)
        }

        let execEvents: [es_event_type_t] = [ ES_EVENT_TYPE_AUTH_EXEC ]
        if es_subscribe(client, execEvents, UInt32(execEvents.count)) == ES_RETURN_SUCCESS {
            Logfile.es.log("Subscribed to AUTH_EXEC")
        } else {
            Logfile.es.error("es_subscribe AUTH_EXEC failed")
        }

        ESManager.sharedInstanceForCallbacks = self
        scheduleTempCleanup()
    }

    private func stop() {
        if let client { es_delete_client(client) }
        client = nil
        
        ESManager.sharedInstanceForCallbacks = nil

        if let l = listener {
            l.delegate = nil
            listener = nil
        }
        activeConnectionsQueue.sync {
            for conn in activeConnections { conn.invalidate() }
            activeConnections.removeAll()
        }

        watchersQueue.sync {
            for (_, source) in watchers { source.cancel() }
            watchers.removeAll()
        }
    }
}

// MARK: - Mach Service XPC setup
extension ESManager {
    private func setupMachListener() {
        let l = NSXPCListener(machServiceName: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc")
        l.delegate = self
        l.resume()
        self.listener = l
        Logfile.es.log("MachService XPC listener resumed: endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc")
    }
    
    private func withRetryPickAppConnection(
        maxRetries: Int = 6,
        delays: [TimeInterval] = [0.0, 0.01, 0.02, 0.05, 0.1, 0.25],
        completion: @escaping (NSXPCConnection?) -> Void
    ) {
        func attempt(_ idx: Int) {
            if let conn = self.pickAppConnection() {
                Logfile.es.log("Got active XPC connection on attempt #\(idx + 1, privacy: .public)")
                completion(conn)
                return
            }
            if idx >= min(maxRetries - 1, delays.count - 1) {
                Logfile.es.log("No XPC connection after quick retries (attempts=\(idx + 1, privacy: .public), giving up)")
                completion(nil)
                return
            }
            let delay = delays[min(idx + 1, delays.count - 1)]
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                attempt(idx + 1)
            }
        }
        attempt(0)
    }
    
    private func storeIncomingConnection(_ conn: NSXPCConnection) {
        activeConnectionsQueue.async {
            self.activeConnections.append(conn)
            Logfile.es.log("Stored incoming XPC connection — total=\(self.activeConnections.count, privacy: .public)")
        }
    }
    
    private func removeIncomingConnection(_ conn: NSXPCConnection) {
        activeConnectionsQueue.async {
            self.activeConnections.removeAll { $0 === conn }
            Logfile.es.log("Removed XPC connection — total=\(self.activeConnections.count, privacy: .public)")
        }
    }
    
    private func pickAppConnection() -> NSXPCConnection? {
        var connOut: NSXPCConnection? = nil
        activeConnectionsQueue.sync { connOut = self.activeConnections.first }
        return connOut
    }
}

// MARK: - Blocked Apps list update
extension ESManager {
    // sync notify to app when a blocked exec occurs
    private func sendBlockedNotificationToApp(name: String, path: String, sha: String) {
        withRetryPickAppConnection { conn in
            guard let conn else {
                Logfile.es.log("No XPC connection available after retries — cannot notify app")
                return
            }

            if let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                Logfile.es.error("XPC notify (async) error: \(String(describing: error), privacy: .public)")
            }) as? ESXPCProtocol {
                proxy.notifyBlockedExec(name: name, path: path, sha: sha)
                Logfile.es.log("Notified app (async) about blocked exec: \(path, privacy: .public)")
                return
            }

            if let syncProxy = conn.synchronousRemoteObjectProxyWithErrorHandler({ error in
                Logfile.es.error("XPC notify (sync) error: \(String(describing: error), privacy: .public)")
            }) as? ESXPCProtocol {
                syncProxy.notifyBlockedExec(name: name, path: path, sha: sha)
                Logfile.es.log("Notified app (sync fallback) about blocked exec: \(path, privacy: .public)")
                return
            }

            Logfile.es.error("Failed to obtain any proxy for notifyBlockedExec")
        }
    }

    // App -> Extension: updateBlockedApps receives NSArray
    @objc func updateBlockedApps(_ apps: NSArray) {
        var shas: [String] = []
        var pathToSha: [String: String] = [:]
        for item in apps {
            if let dict = item as? [String: Any], let sha = dict["sha256"] as? String {
                shas.append(sha)
                if let path = dict["path"] as? String {
                    pathToSha[path] = sha
                }
                Logfile.es.log("updateBlockedApps received SHA: \(sha, privacy: .public)")
            } else if let dict = item as? NSDictionary, let sha = dict["sha256"] as? String {
                shas.append(sha)
                if let path = dict["path"] as? String { pathToSha[path] = sha }
                Logfile.es.log("updateBlockedApps received SHA (NSDictionary): \(sha, privacy: .public)")
            }
        }
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            self.blockedSHAs = Set(shas)
            for (p, s) in pathToSha { self.blockedPathToSHA[p] = s }
            Logfile.es.log("updateBlockedApps set blockedSHAs (\(shas.count) items)")
        }
    }
}

// MARK: - Temp allow SHA to run
extension ESManager {
    private func allowTempSHA(_ sha: String) {
        tempQueue.async { [weak self] in
            guard let self = self else { return }
            let expiry = Date().addingTimeInterval(self.allowWindowSeconds)
            self.tempAllowedSHAs[sha] = expiry
            Logfile.es.log("Temp allowed SHA: \(sha, privacy: .public) until \(expiry, privacy: .public)")
        }
    }

    // App -> Extension: allowSHAOnce with reply
    @objc func allowSHAOnce(_ sha: String, withReply reply: @escaping (Bool) -> Void) {
        allowTempSHA(sha)
        reply(true)
    }
}

// MARK: - Watching and auto update list locked app
extension ESManager {
    private func reloadConfigIfAvailable(from url: URL) {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            Logfile.es.log("Config not found at \(path, privacy: .public)")
            return
        }
        reloadConfig(from: url)
    }

    private func reloadConfig(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            var shas: [String] = []
            var pathToSha: [String: String] = [:]

            if let dict = plist as? [String: Any], let arr = dict["BlockedApps"] as? [[String: Any]] {
                for item in arr {
                    if let sha = item["sha256"] as? String {
                        shas.append(sha)
                        if let path = item["path"] as? String { pathToSha[path] = sha }
                        Logfile.es.log("Found SHA in plist: \(sha, privacy: .public)")
                    }
                }
            } else if let arr = plist as? [[String: Any]] {
                for item in arr {
                    if let sha = item["sha256"] as? String {
                        shas.append(sha)
                        if let path = item["path"] as? String { pathToSha[path] = sha }
                        Logfile.es.log("Found SHA in plist array: \(sha, privacy: .public)")
                    }
                }
            } else if let arr = plist as? NSArray {
                for item in arr {
                    if let d = item as? NSDictionary, let sha = d["sha256"] as? String {
                        shas.append(sha)
                        if let path = d["path"] as? String { pathToSha[path] = sha }
                        Logfile.es.log("Found SHA in NSArray: \(sha, privacy: .public)")
                    }
                }
            } else {
                Logfile.es.log("Unsupported plist format at \(url.path, privacy: .public)")
            }

            stateQueue.async { [weak self] in
                guard let self = self else { return }
                self.blockedSHAs = Set(shas)
                for (p, s) in pathToSha { self.blockedPathToSHA[p] = s }
                Logfile.es.log("Loaded \(shas.count) blocked SHAs from \(url.path, privacy: .public)")
            }
        } catch {
            Logfile.es.error("Failed to load config at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startWatchingConfig(at url: URL) {
        let path = url.path
        watchersQueue.async { [weak self] in
            guard let self = self else { return }

            if let existing = self.watchers[path] {
                existing.cancel()
                self.watchers.removeValue(forKey: path)
            }

            var fd = open(path, O_EVTONLY)
            if fd < 0 {
                let parent = url.deletingLastPathComponent().path
                Logfile.es.log("File \(path, privacy: .public) missing — watching parent dir \(parent, privacy: .public)")
                let parentFD = open(parent, O_EVTONLY)
                if parentFD < 0 {
                    Logfile.es.error("Failed to open parent dir \(parent, privacy: .public)")
                    return
                } else {
                    fd = parentFD
                }
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename],
                queue: DispatchQueue.global()
            )

            source.setEventHandler { [weak self] in
                guard let self = self else { return }

                if self.isReloadingConfig { return }
                self.isReloadingConfig = true

                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    defer { self.isReloadingConfig = false }
                    Logfile.es.log("File event triggered reload for \(path, privacy: .public)")

                    do {
                        let data = try Data(contentsOf: url)
                        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                        guard let dict = plist as? [String: Any], let lockedAppsArray = dict["BlockedApps"] as? [[String: Any]] else {
                            Logfile.es.error("Invalid plist structure at \(url.path)")
                            return
                        }

                        var esApps: [String: LockedAppConfig] = [:]
                        var pathToSha: [String: String] = [:]
                        var shas: [String] = []

                        for appDict in lockedAppsArray {
                            if let blockMode = appDict["blockMode"] as? String, blockMode == "ES",
                               let bundleID = appDict["bundleID"] as? String,
                               let path = appDict["path"] as? String,
                               let sha256 = appDict["sha256"] as? String {
                                let execFile = appDict["execFile"] as? String
                                let name = appDict["name"] as? String ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                                let cfg = LockedAppConfig(bundleID: bundleID, path: path, sha256: sha256, blockMode: blockMode, execFile: execFile, name: name)
                                esApps[path] = cfg
                                pathToSha[path] = sha256
                                shas.append(sha256)
                            }
                        }

                        DispatchQueue.main.async {
                            self.lockedApps = esApps
                            Logfile.es.log("Reloaded ES apps: \(esApps.count) items")
                        }

                        self.stateQueue.async {
                            for (p, s) in pathToSha { self.blockedPathToSHA[p] = s }
                            self.blockedSHAs = Set(shas)
                        }

                    } catch {
                        Logfile.es.error("Failed to read plist: \(error.localizedDescription)")
                    }
                }

                let flags = source.data
                if flags.contains(.delete) || flags.contains(.rename) {
                    source.cancel()
                    close(fd)
                    self.watchersQueue.asyncAfter(deadline: .now() + .milliseconds(150)) {
                        self.startWatchingConfig(at: url)
                    }
                }
            }

            source.setCancelHandler { close(fd) }
            self.watchers[path] = source
            source.resume()
            Logfile.es.log("Started watcher on \(path, privacy: .public)")
        }
    }
}

// MARK: - Compute app info
extension ESManager {
    // Compute SHA256 hash synchronously (used on background queues only)
    private func computeSHA256Streaming(forPath path: String) -> String? {
        let fh: FileHandle
        do {
            fh = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        } catch {
            return nil
        }
        defer { try? fh.close() }

        var hasher = SHA256()
        while true {
            let chunkData = fh.readData(ofLength: 64 * 1024) // 64KB
            if chunkData.count == 0 { break }
            hasher.update(data: chunkData)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // Compute a reasonable app name based on path. Not used on hot-path.
    private func computeAppName(forExecPath path: String) -> String {
        let execFile = URL(fileURLWithPath: path)
        let appBundleURL = execFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var appName = appBundleURL.deletingPathExtension().lastPathComponent
        if let bundle = Bundle(url: appBundleURL) {
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String { appName = displayName }
            else if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String { appName = name }
        }
        return appName
    }
}

// MARK: - Handle Message
extension ESManager {
    private static func handleMessage(client: OpaquePointer?, message: UnsafePointer<es_message_t>?) {
        guard let client, let message else { return }
        let msg = message.pointee

        if msg.event_type == ES_EVENT_TYPE_AUTH_EXEC {
            guard let path = safePath(fromFilePointer: msg.event.exec.target.pointee.executable) else {
                Logfile.es.log("Missing exec path in AUTH_EXEC. Denying by default.")
                es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
                return
            }

            guard let mgr = ESManager.sharedInstanceForCallbacks else {
                Logfile.es.log("No ESManager instance. Denying exec.")
                es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
                return
            }

            // Hot-path: O(1) checks using path and pre-populated maps/caches
            // 1) If we have a mapped SHA for this exact path, use it for decision (fast)
            if let mappedSHA = mgr.stateQueue.sync(execute: { mgr.blockedPathToSHA[path] }) {
                // If temp allowed for this SHA -> allow
                if mgr.isTempAllowed(mappedSHA) {
                    respondWithDeadline(ES_AUTH_RESULT_ALLOW, client: client, message: message)
                    Logfile.es.log("Temp allowed by SHA mapping for \(path, privacy: .public)")
                    return
                }

                let isBlocked = mgr.stateQueue.sync(execute: { mgr.blockedSHAs.contains(mappedSHA) })
                if isBlocked {
                    respondWithDeadline(ES_AUTH_RESULT_DENY, client: client, message: message)
                    Logfile.es.log("Denied by mapped SHA for \(path, privacy: .public)")

                    DispatchQueue.global(qos: .utility).async {
                        let name = mgr.computeAppName(forExecPath: path)
                        mgr.sendBlockedNotificationToApp(name: name, path: path, sha: mappedSHA)
                    }
                    return
                } else {
                    respondWithDeadline(ES_AUTH_RESULT_ALLOW, client: client, message: message)
                    Logfile.es.log("Allowed by mapped SHA for \(path, privacy: .public)")
                    return
                }
            }

            // 2) If we have a cached decision for this path, apply it
            if let cached = mgr.decisionQueue.sync(execute: { mgr.decisionCache[path] }) {
                switch cached {
                case .allow:
                    respondWithDeadline(ES_AUTH_RESULT_ALLOW, client: client, message: message)
                    Logfile.es.log("Allowed by cache for \(path, privacy: .public)")
                    return
                case .deny:
                    respondWithDeadline(ES_AUTH_RESULT_DENY, client: client, message: message)
                    Logfile.es.log("Denied by cache for \(path, privacy: .public)")
                    let shaOpt = mgr.stateQueue.sync(execute: { mgr.blockedPathToSHA[path] })
                    DispatchQueue.global(qos: .utility).async {
                        let name = mgr.computeAppName(forExecPath: path)
                        mgr.sendBlockedNotificationToApp(name: name, path: path, sha: shaOpt ?? "")
                    }
                    return
                }
            }

            // 3) No fast decision available — compute SHA synchronously and decide immediately
            if let sha = mgr.computeSHA256Streaming(forPath: path) {
                // If temp allowed for this SHA -> allow
                if mgr.isTempAllowed(sha) {
                    es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
                    Logfile.es.log("Temp allowed by computed SHA for \(path, privacy: .public)")
                    // cache mapping and allow decision for future hot-paths
                    mgr.stateQueue.async { mgr.blockedPathToSHA[path] = sha }
                    mgr.decisionQueue.async { mgr.decisionCache[path] = .allow }
                    return
                }

                // Check authoritative blocklist synchronously
                let isBlockedNow = mgr.stateQueue.sync(execute: { mgr.blockedSHAs.contains(sha) })
                if isBlockedNow {
                    // Block immediately
                    es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
                    Logfile.es.log("Denied (sync SHA) for \(path, privacy: .public) • SHA=\(sha, privacy: .public)")

                    // Cache mapping & deny decision to make future lookups O(1)
                    mgr.stateQueue.async { mgr.blockedPathToSHA[path] = sha }
                    mgr.decisionQueue.async { mgr.decisionCache[path] = .deny }

                    // Notify app asynchronously
                    DispatchQueue.global(qos: .utility).async {
                        let name = mgr.computeAppName(forExecPath: path)
                        mgr.sendBlockedNotificationToApp(name: name, path: path, sha: sha)
                    }
                    return
                } else {
                    // Not blocked — allow and cache for future
                    es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
                    Logfile.es.log("Allowed (sync SHA) for \(path, privacy: .public) • SHA=\(sha, privacy: .public)")
                    mgr.stateQueue.async { mgr.blockedPathToSHA[path] = sha }
                    mgr.decisionQueue.async { mgr.decisionCache[path] = .allow }
                    return
                }
            } else {
                // Could not compute SHA synchronously (I/O/read error)
                // Deny by default to ensure first-run is blocked; change to ALLOW if you prefer permissive behavior.
                es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
                Logfile.es.log("Failed to compute SHA synchronously for \(path, privacy: .public) — denying by default")
                return
            }
        }
    }
}

// MARK: - NSXPCListenerDelegate extension
extension ESManager {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        Logfile.es.log("Incoming XPC connection attempt (pid=\(newConnection.processIdentifier, privacy: .public))")

        newConnection.exportedInterface = NSXPCInterface(with: ESAppProtocol.self)
        newConnection.exportedObject = self

        newConnection.remoteObjectInterface = NSXPCInterface(with: ESXPCProtocol.self)

        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self = self, let conn = newConnection else { return }
            Logfile.es.log("Incoming XPC connection invalidated")
            self.removeIncomingConnection(conn)
        }

        newConnection.interruptionHandler = {
            Logfile.es.log("Incoming XPC connection interrupted")
        }

        storeIncomingConnection(newConnection)
        newConnection.resume()
        Logfile.es.log("Accepted new XPC connection from client")
        return true
    }
}
