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

@objcMembers
final class ESManager: NSObject, NSXPCListenerDelegate {
    static var sharedInstanceForCallbacks: ESManager?
    @Published var lockedApps: [String: LockedAppConfig] = [:]
    
    private var client: OpaquePointer?
    
    private var blockedSHAs: Set<String> = []
    fileprivate let stateQueue = DispatchQueue(label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.state")
    
    private var tempAllowedSHAs: [String: Date] = [:]
    private let tempQueue = DispatchQueue(label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.temp")
    private let allowWindowSeconds: TimeInterval = 10
    
    // Allowed PIDs for config access (set by app via XPC). Value = expiry Date
    private var allowedPIDs: [pid_t: Date] = [:]
    private let allowedPIDsQueue = DispatchQueue(label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.allowedPIDs")
    private let allowedPIDWindowSeconds: TimeInterval = 5.0  // thời gian allow (tùy chỉnh)
    
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
    
    private func start() throws {
        setupMachListener()
        
        var client: OpaquePointer?
        let res = es_new_client(&client) { client, message in
            ESManager.handleMessage(client: client, message: message)
        }
        
        guard res == ES_NEW_CLIENT_RESULT_SUCCESS, let client else {
            Logfile.es.error("es_new_client failed: \(String(describing: res), privacy: .public)")
            throw NSError(domain: "ESManager", code: 1, userInfo: nil)
        }

        // MARK: - Đăng ký từng nhóm event riêng biệt
        // 1️⃣ AUTH_EXEC
        let execEvents: [es_event_type_t] = [
            ES_EVENT_TYPE_AUTH_EXEC
        ]
        if es_subscribe(client, execEvents, UInt32(execEvents.count)) == ES_RETURN_SUCCESS {
            Logfile.es.log("✅ Subscribed to AUTH_EXEC")
        } else {
            Logfile.es.error("❌ es_subscribe AUTH_EXEC failed")
        }

//        // 2️⃣ AUTH_OPEN
//        let openEvents: [es_event_type_t] = [
//            ES_EVENT_TYPE_AUTH_OPEN
//        ]
//        if es_subscribe(client, openEvents, UInt32(openEvents.count)) == ES_RETURN_SUCCESS {
//            Logfile.es.log("✅ Subscribed to AUTH_OPEN")
//        } else {
//            Logfile.es.error("❌ es_subscribe AUTH_OPEN failed")
//        }
//
//        // 3️⃣ AUTH_TRUNCATE
//        let truncateEvents: [es_event_type_t] = [
//            ES_EVENT_TYPE_AUTH_TRUNCATE
//        ]
//        if es_subscribe(client, truncateEvents, UInt32(truncateEvents.count)) == ES_RETURN_SUCCESS {
//            Logfile.es.log("✅ Subscribed to AUTH_TRUNCATE")
//        } else {
//            Logfile.es.error("❌ es_subscribe AUTH_TRUNCATE failed")
//        }

        ESManager.sharedInstanceForCallbacks = self

        candidateConfigURLs.forEach { url in
            reloadConfigIfAvailable(from: url)
            startWatchingConfig(at: url)
        }

        scheduleTempCleanup()
    }
    
    private func stop() {
        if let client { es_delete_client(client) }
        client = nil
        
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
    
    // MARK: Mach Service XPC setup
    private func setupMachListener() {
        let l = NSXPCListener(machServiceName: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc")
        l.delegate = self
        l.resume()
        self.listener = l
        Logfile.es.log("🔌 MachService XPC listener resumed: endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc")
    }
    
    private func withRetryPickAppConnection(
        maxRetries: Int = 6,
        delays: [TimeInterval] = [0.0, 0.01, 0.02, 0.05, 0.1, 0.25],
        completion: @escaping (NSXPCConnection?) -> Void
    ) {
        func attempt(_ idx: Int) {
            if let conn = self.pickAppConnection() {
                Logfile.es.log("🔗 Got active XPC connection on attempt #\(idx + 1, privacy: .public)")
                completion(conn)
                return
            }
            if idx >= min(maxRetries - 1, delays.count - 1) {
                Logfile.es.log("❌ No XPC connection after quick retries (attempts=\(idx + 1, privacy: .public), giving up)")
                completion(nil)
                return
            }
            let delay = delays[min(idx + 1, delays.count - 1)]
            // tiny async retry — keep total waiting low (< ~0.5s)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                attempt(idx + 1)
            }
        }
        attempt(0)
    }
    
    private func storeIncomingConnection(_ conn: NSXPCConnection) {
        activeConnectionsQueue.async {
            self.activeConnections.append(conn)
            Logfile.es.log("➕ Stored incoming XPC connection — total=\(self.activeConnections.count, privacy: .public)")
        }
    }
    
    private func removeIncomingConnection(_ conn: NSXPCConnection) {
        activeConnectionsQueue.async {
            self.activeConnections.removeAll { $0 === conn }
            Logfile.es.log("➖ Removed XPC connection — total=\(self.activeConnections.count, privacy: .public)")
        }
    }
    
    private func pickAppConnection() -> NSXPCConnection? {
        var connOut: NSXPCConnection? = nil
        activeConnectionsQueue.sync { connOut = self.activeConnections.first }
        return connOut
    }
    
    // New: async notify to app when a blocked exec occurs
    private func sendBlockedNotificationToApp(name: String, path: String, sha: String) {
        withRetryPickAppConnection { conn in
            guard let conn else {
                Logfile.es.log("❌ No XPC connection available after retries — cannot notify app")
                return
            }
            
            // Prefer async non-blocking proxy (fast). If it errors, we try sync fallback.
            if let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                Logfile.es.error("XPC notify (async) error: \(String(describing: error), privacy: .public)")
            }) as? ESXPCProtocol {
                proxy.notifyBlockedExec(name: name, path: path, sha: sha)
                Logfile.es.log("📣 Notified app (async) about blocked exec: \(path, privacy: .public)")
                return
            }
            
            // Fallback: synchronous proxy with small implicit blocking (use carefully)
            if let syncProxy = conn.synchronousRemoteObjectProxyWithErrorHandler({ error in
                Logfile.es.error("XPC notify (sync) error: \(String(describing: error), privacy: .public)")
            }) as? ESXPCProtocol {
                // This will block the thread until message delivered or remote errors.
                syncProxy.notifyBlockedExec(name: name, path: path, sha: sha)
                Logfile.es.log("📣 Notified app (sync fallback) about blocked exec: \(path, privacy: .public)")
                return
            }
            
            Logfile.es.error("❌ Failed to obtain any proxy for notifyBlockedExec")
        }
    }
    
    private func allowTempSHA(_ sha: String) {
        tempQueue.async { [weak self] in
            guard let self = self else { return }
            let expiry = Date().addingTimeInterval(self.allowWindowSeconds)
            self.tempAllowedSHAs[sha] = expiry
            
            Logfile.es.log("🔓 Temp allowed SHA: \(sha, privacy: .public) until \(expiry, privacy: .public)")
        }
    }
    
    // App -> Extension: allowSHAOnce with reply
    @objc func allowSHAOnce(_ sha: String, withReply reply: @escaping (Bool) -> Void) {
        allowTempSHA(sha)
        reply(true)
    }
    
    // App -> Extension: updateBlockedApps receives NSArray
    @objc func updateBlockedApps(_ apps: NSArray) {
        var shas: [String] = []
        for item in apps {
            if let dict = item as? [String: Any], let sha = dict["sha256"] as? String {
                shas.append(sha)
                Logfile.es.log("📤 updateBlockedApps received SHA: \(sha, privacy: .public)")
            } else if let dict = item as? NSDictionary, let sha = dict["sha256"] as? String {
                shas.append(sha)
                Logfile.es.log("📤 updateBlockedApps received SHA (NSDictionary): \(sha, privacy: .public)")
            }
        }
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            self.blockedSHAs = Set(shas)
            Logfile.es.log("🔄 updateBlockedApps set blockedSHAs (\(shas.count) items): \(shas.joined(separator: ", "), privacy: .public)")
        }
    }
    
    // App -> Extension: request access for config
    @objc func allowConfigAccess(_ pid: Int32, withReply reply: @escaping (Bool) -> Void) {
        let p = pid_t(pid)
        allowedPIDsQueue.async { [weak self] in
            guard let self = self else { reply(false); return }
            let expiry = Date().addingTimeInterval(self.allowedPIDWindowSeconds)
            self.allowedPIDs[p] = expiry
            Logfile.es.log("🔓 allowConfigAccess granted for pid=\(p, privacy: .public) until \(expiry, privacy: .public)")
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
            if !removedSHAs.isEmpty { Logfile.es.log("⌛ Temp allowed SHAs expired: \(removedSHAs.count, privacy: .public)") }
        }
        
    }
    
    private func isTempAllowed(_ sha: String) -> Bool {
        return tempQueue.sync {
            if let expiry = tempAllowedSHAs[sha], expiry > Date() { return true }
            return false
        }
    }
    
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
            
            if let dict = plist as? [String: Any],
               let arr = dict["BlockedApps"] as? [[String: Any]] {
                for item in arr {
                    if let sha = item["sha256"] as? String {
                        shas.append(sha)
                        Logfile.es.log("📄 Found SHA in plist: \(sha, privacy: .public)")
                    }
                }
            } else if let arr = plist as? [[String: Any]] {
                for item in arr {
                    if let sha = item["sha256"] as? String {
                        shas.append(sha)
                        Logfile.es.log("📄 Found SHA in plist array: \(sha, privacy: .public)")
                    }
                }
            } else if let arr = plist as? NSArray {
                for item in arr {
                    if let d = item as? NSDictionary,
                       let sha = d["sha256"] as? String {
                        shas.append(sha)
                        Logfile.es.log("📄 Found SHA in NSArray: \(sha, privacy: .public)")
                    }
                }
            } else {
                Logfile.es.log("⚠️ Unsupported plist format at \(url.path, privacy: .public)")
            }
            
            stateQueue.async { [weak self] in
                guard let self = self else { return }
                self.blockedSHAs = Set(shas)
                Logfile.es.log("🔄 Loaded \(shas.count) blocked SHAs from \(url.path, privacy: .public): \(shas.joined(separator: ", "), privacy: .public)")
            }
        } catch {
            Logfile.es.error("❌ Failed to load config at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func startWatchingConfig(at url: URL) {
        let path = url.path
        watchersQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel watcher cũ nếu có
            if let existing = self.watchers[path] {
                existing.cancel()
                self.watchers.removeValue(forKey: path)
            }
            
            // Mở file để watch
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

                // Chặn recursion: nếu đang reload thì skip
                if self.isReloadingConfig { return }
                self.isReloadingConfig = true

                // Delay nhẹ để hệ thống xử lý xong AUTH_OPEN chain
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    defer { self.isReloadingConfig = false }
                    Logfile.es.log("📣 File event triggered reload for \(path, privacy: .public)")

                    do {
                        let data = try Data(contentsOf: url)
                        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                        guard let dict = plist as? [String: Any],
                              let lockedAppsArray = dict["BlockedApps"] as? [[String: Any]] else {
                            Logfile.es.error("❌ Invalid plist structure at \(url.path)")
                            return
                        }

                        var esApps: [String: LockedAppConfig] = [:]
                        for appDict in lockedAppsArray {
                            if let blockMode = appDict["blockMode"] as? String, blockMode == "ES",
                               let bundleID = appDict["bundleID"] as? String,
                               let path = appDict["path"] as? String,
                               let sha256 = appDict["sha256"] as? String {
                                let execFile = appDict["execFile"] as? String
                                let name = appDict["name"] as? String ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                                let cfg = LockedAppConfig(bundleID: bundleID, path: path, sha256: sha256, blockMode: blockMode, execFile: execFile, name: name)
                                esApps[path] = cfg
                            }
                        }

                        DispatchQueue.main.async {
                            self.lockedApps = esApps
                            Logfile.es.log("✅ Reloaded ES apps: \(esApps.count) items")
                        }

                    } catch {
                        Logfile.es.error("❌ Failed to read plist: \(error.localizedDescription)")
                    }
                }

                // Nếu file bị xoá hoặc rename thì restart watcher
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
            Logfile.es.log("👀 Started watcher on \(path, privacy: .public)")
        }
    }
    
    private static func safePath(fromFilePointer filePtr: UnsafePointer<es_file_t>?) -> String? {
        guard let filePtr = filePtr else { return nil }
        let file = filePtr.pointee
        guard let data = file.path.data else { return nil }
        return String(cString: data)
    }

    private static func safeExecPath(fromProcPointer procPtr: UnsafePointer<es_process_t>?) -> String? {
        guard let procPtr else { return nil }

        // Ép kiểu sang Optional pointer để có thể check nil
        let execPtr: UnsafeMutablePointer<es_file_t>? = procPtr.pointee.executable

        guard let validExecPtr = execPtr,
              let data = validExecPtr.pointee.path.data else {
            return nil
        }

        let path = String(cString: data)
        if path.isEmpty { return nil }

        return path
    }

    private static func handleMessage(client: OpaquePointer?, message: UnsafePointer<es_message_t>?) {
        guard let client, let message else { return }
        let msg = message.pointee

//        // --- xử lý AUTH_OPEN / AUTH_TRUNCATE để bảo vệ file config ---
//        if msg.event_type == ES_EVENT_TYPE_AUTH_OPEN || msg.event_type == ES_EVENT_TYPE_AUTH_TRUNCATE {
//            var accessedPath: String? = nil
//
//            switch msg.event_type {
//            case ES_EVENT_TYPE_AUTH_OPEN:
//                accessedPath = safePath(fromFilePointer: msg.event.open.file)
//            case ES_EVENT_TYPE_AUTH_TRUNCATE:
//                accessedPath = safePath(fromFilePointer: msg.event.truncate.target)
//            default:
//                break
//            }
//
//            guard let accessed = accessedPath else {
//                Logfile.es.log("⚠️ Missing accessedPath in AUTH event (possibly NULL file path). Denying by default.")
//                es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
//                return
//            }
//
//            let accCanonical = URL(fileURLWithPath: accessed)
//                .standardized.resolvingSymlinksInPath().path
//
//            let protected = (ESManager.sharedInstanceForCallbacks?.candidateConfigURLs ?? []).map {
//                $0.standardized.resolvingSymlinksInPath().path
//            }
//
//            // --- chỉ log nếu file nằm trong protected ---
//            if protected.contains(accCanonical) {
//                Logfile.es.log("🔹 AUTH event: \(msg.event_type == ES_EVENT_TYPE_AUTH_OPEN ? "OPEN" : "TRUNCATE"), path: \(accCanonical, privacy: .public)")
//
//                let procPtr = msg.process
//                guard safeExecPath(fromProcPointer: procPtr) != nil else {
//                    Logfile.es.log("⚠️ Missing proc executable path. Denying access to \(accCanonical, privacy: .public)")
//                    es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
//                    return
//                }
//
//                let callerPID = audit_token_to_pid(procPtr.pointee.audit_token)
//                if callerPID == getpid() {
//                    Logfile.es.log("⚠️ Self-open recursion detected → allowed self access")
//                    es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
//                    return
//                }
//
//                var pidAllowed = false
//                ESManager.sharedInstanceForCallbacks?.allowedPIDsQueue.sync {
//                    if let expiry = ESManager.sharedInstanceForCallbacks?.allowedPIDs[callerPID], expiry > Date() {
//                        pidAllowed = true
//                        ESManager.sharedInstanceForCallbacks?.allowedPIDs.removeValue(forKey: callerPID)
//                    }
//                }
//
//                if pidAllowed {
//                    es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
//                    Logfile.es.log("✅ Allowed (by XPC request) pid=\(callerPID, privacy: .public) for \(accCanonical, privacy: .public)")
//                } else {
//                    es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
//                    Logfile.es.log("⛔ Denied pid=\(callerPID, privacy: .public) accessing \(accCanonical, privacy: .public)")
//                }
//            } else {
//                // Không log gì nếu file không nằm trong danh sách config
//                es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
//            }
//        }

        // --- xử lý AUTH_EXEC (block app theo SHA) ---
        if msg.event_type == ES_EVENT_TYPE_AUTH_EXEC {
            let target = msg.event.exec.target.pointee
            guard let path = safePath(fromFilePointer: target.executable) else {
                Logfile.es.log("⚠️ Missing exec path in AUTH_EXEC. Denying by default.")
                es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
                return
            }

            let sha = URL(fileURLWithPath: path).sha256() ?? ""

            // Đi lên tìm bundle .app
            let execFile = URL(fileURLWithPath: path)
            let appBundleURL = execFile.deletingLastPathComponent() // .../Contents/MacOS
                .deletingLastPathComponent()                       // .../Contents
                .deletingLastPathComponent()                       // .../MyApp.app

            var appName = appBundleURL.deletingPathExtension().lastPathComponent
            if let bundle = Bundle(url: appBundleURL) {
                if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                    appName = displayName
                } else if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                    appName = name
                }
            }

            guard let mgr = ESManager.sharedInstanceForCallbacks else {
                Logfile.es.log("⚠️ No ESManager instance. Denying exec.")
                es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
                return
            }

            let blocked = mgr.stateQueue.sync { mgr.blockedSHAs }
            Logfile.es.log("🔔 AUTH_EXEC Event: path=\(path, privacy: .public), computed SHA=\(sha, privacy: .public)")

            // Nếu được allow tạm thời
            if mgr.isTempAllowed(sha) {
                es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
                Logfile.es.log("✅ Temp allowed: \(path, privacy: .public)")
                mgr.tempQueue.async {
                    mgr.tempAllowedSHAs.removeValue(forKey: sha)
                }
                return
            }

            if blocked.contains(sha) {
                mgr.sendBlockedNotificationToApp(name: appName, path: path, sha: sha)
                es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
                Logfile.es.log("❌ Denied by default and notified app: \(path, privacy: .public)")
                return
            }

            es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
            Logfile.es.log("✅ Allowed: \(path, privacy: .public) • SHA=\(sha, privacy: .public)")
            return
        }
    }
}

// MARK: - NSXPCListenerDelegate
extension ESManager {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        Logfile.es.log("➡️ Incoming XPC connection attempt (pid=\(newConnection.processIdentifier, privacy: .public))")

        // Export the protocol that the extension implements (so app can call these methods)
        newConnection.exportedInterface = NSXPCInterface(with: ESAppProtocol.self)
        newConnection.exportedObject = self

        // Allow the extension to call back to the app using ESXPCProtocol
        newConnection.remoteObjectInterface = NSXPCInterface(with: ESXPCProtocol.self)

        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self = self, let conn = newConnection else { return }
            Logfile.es.log("❌ Incoming XPC connection invalidated")
            self.removeIncomingConnection(conn)
        }

        newConnection.interruptionHandler = {
            Logfile.es.log("⚠️ Incoming XPC connection interrupted")
        }

        storeIncomingConnection(newConnection)
        newConnection.resume()
        Logfile.es.log("✅ Accepted new XPC connection from client")
        return true
    }
}

