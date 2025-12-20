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

enum ESError: Error {
    case fullDiskAccessMissing    // ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED
    case notRoot                  // ES_NEW_CLIENT_RESULT_ERR_NOT_PRIVILEGED
    case entitlementMissing       // ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED
    case tooManyClients           // ES_NEW_CLIENT_RESULT_ERR_TOO_MANY_CLIENTS
    case internalError            // ES_NEW_CLIENT_RESULT_ERR_INTERNAL
    case invalidArgument          // ES_NEW_CLIENT_RESULT_ERR_INVALID_ARGUMENT
    case unknown(Int32)
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
    private let decisionQueue = DispatchQueue(label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.cache")

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

// MARK: - Lifecycle setup
extension ESManager {
    private func start() throws {
        setupMachListener()

        let res = es_new_client(&self.client) { client, message in
            ESManager.handleMessage(client: client, message: message)
        }

        // Kiểm tra nếu không thành công
        if res != ES_NEW_CLIENT_RESULT_SUCCESS {
            Logfile.es.error("es_new_client failed with result: \(res.rawValue)")
            
            switch res {
            case ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED:
                throw ESError.fullDiskAccessMissing
            case ES_NEW_CLIENT_RESULT_ERR_NOT_PRIVILEGED:
                throw ESError.notRoot
            case ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED:
                throw ESError.entitlementMissing
            case ES_NEW_CLIENT_RESULT_ERR_TOO_MANY_CLIENTS:
                throw ESError.tooManyClients
            case ES_NEW_CLIENT_RESULT_ERR_INVALID_ARGUMENT:
                throw ESError.invalidArgument
            case ES_NEW_CLIENT_RESULT_ERR_INTERNAL:
                throw ESError.internalError
            default:
                throw ESError.unknown(Int32(res.rawValue))
            }
        }

        guard let client = self.client else {
            throw ESError.internalError
        }

        let execEvents: [es_event_type_t] = [ ES_EVENT_TYPE_AUTH_EXEC ]
        if es_subscribe(client, execEvents, UInt32(execEvents.count)) != ES_RETURN_SUCCESS {
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

// MARK: - TTY Notifier (Santa Style)
final class TTYNotifier {
    
    /// Tìm đường dẫn TTY của một Process ID (ví dụ: /dev/ttys001)
    static func getTTYPath(for pid: pid_t) -> String? {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return nil }
        
        let fdInfoSize = MemoryLayout<proc_fdinfo>.stride
        let numFDs = Int(bufferSize) / fdInfoSize
        var fdInfos = [proc_fdinfo](repeating: proc_fdinfo(), count: numFDs)
        
        let result = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdInfos, bufferSize)
        guard result > 0 else { return nil }
        
        for fd in fdInfos {
            if fd.proc_fdtype == PROX_FDTYPE_VNODE {
                var vnodeInfo = vnode_fdinfowithpath()
                let vnodeSize = Int32(MemoryLayout<vnode_fdinfowithpath>.stride)
                let len = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &vnodeInfo, vnodeSize)
                
                if len > 0 {
                    let path = withUnsafePointer(to: &vnodeInfo.pvip.vip_path) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                            String(cString: $0)
                        }
                    }
                    if path.hasPrefix("/dev/tty") { return path }
                }
            }
        }
        return nil
    }

    /// Gửi thông báo chặn vào Terminal
    static func notify(parentPid: pid_t, blockedPath: String, sha: String, identifier: String? = nil) {
        guard let ttyPath = getTTYPath(for: parentPid) else { return }
        
        // Mở TTY để ghi
        guard let fileHandle = FileHandle(forWritingAtPath: ttyPath) else { return }
        defer { try? fileHandle.close() }
        
        // Message
        let title        = "AppLocker"
        let description  = "The following application has been blocked from execution\nbecause it was added to the locked list."
        
        let labelPath    = "Path:"
        let labelId      = "Identifier:"
        let labelSha     = "SHA256:"
        let labelParent  = "Parent PID:"
        
        // --- PHẦN ĐỊNH DẠNG (FORMATTING) ---
        let boldRed = "\u{001B}[1m\u{001B}[31m"
        let reset   = "\u{001B}[0m"
        let bold    = "\u{001B}[1m"
        
        // --- GỘP LẠI (Dùng String Interpolation) ---
        let message = """
            \(boldRed)\(title)\(reset)
            
            \(description)
            
            \(bold)\(labelPath.padding(toLength: 12, withPad: " ", startingAt: 0))\(reset) \(blockedPath)
            \(bold)\(labelId.padding(toLength: 12, withPad: " ", startingAt: 0))\(reset) \(identifier ?? "Unknown")
            \(bold)\(labelSha.padding(toLength: 12, withPad: " ", startingAt: 0))\(reset) \(sha)
            \(bold)\(labelParent.padding(toLength: 12, withPad: " ", startingAt: 0))\(reset) \(parentPid)
            \n
            """
        
        if let data = message.data(using: .utf8) {
            fileHandle.write(data)
        }
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
            
            // Lấy thông tin process cha (Shell/Launcher) để gửi thông báo
            let parentPid = msg.process.pointee.ppid
            // Lấy Signing ID nếu có (để hiển thị đẹp hơn)
            var signingID = "Unsigned/Unknown"
            if let signingToken = msg.event.exec.target.pointee.signing_id.data {
                signingID = String(cString: signingToken)
            }

            // --- Helper để gửi notify TTY (chạy background để không block kernel response) ---
            func sendTTYNotification(sha: String) {
                DispatchQueue.global(qos: .userInteractive).async {
                    TTYNotifier.notify(parentPid: parentPid, blockedPath: path, sha: sha, identifier: signingID)
                }
            }
            // -------------------------------------------------------------------------------

            // 1) Fast path: Mapped SHA
            if let mappedSHA = mgr.stateQueue.sync(execute: { mgr.blockedPathToSHA[path] }) {
                if mgr.isTempAllowed(mappedSHA) {
                    es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
                    return
                }

                let isBlocked = mgr.stateQueue.sync(execute: { mgr.blockedSHAs.contains(mappedSHA) })
                if isBlocked {
                    // -> DENY
                    usleep(1_000)
                    es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
                    Logfile.es.log("Denied by mapped SHA: \(path)")
                    
                    // Gửi thông báo ra Terminal
                    sendTTYNotification(sha: mappedSHA)

                    DispatchQueue.global(qos: .utility).async {
                        let name = mgr.computeAppName(forExecPath: path)
                        mgr.sendBlockedNotificationToApp(name: name, path: path, sha: mappedSHA)
                    }
                    return
                } else {
                    es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
                    return
                }
            }

            // 2) Cache path
            if let cached = mgr.decisionQueue.sync(execute: { mgr.decisionCache[path] }) {
                switch cached {
                case .allow:
                    es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
                    return
                case .deny:
                    // -> DENY
                    usleep(1_000)
                    es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
                    Logfile.es.log("Denied by cache: \(path)")
                    
                    let shaOpt = mgr.stateQueue.sync(execute: { mgr.blockedPathToSHA[path] }) ?? "Cached-No-SHA"
                    
                    // Gửi thông báo ra Terminal
                    sendTTYNotification(sha: shaOpt)
                    
                    DispatchQueue.global(qos: .utility).async {
                        let name = mgr.computeAppName(forExecPath: path)
                        mgr.sendBlockedNotificationToApp(name: name, path: path, sha: shaOpt)
                    }
                    return
                }
            }

            // 3) Slow path: Compute SHA
            if let sha = mgr.computeSHA256Streaming(forPath: path) {
                if mgr.isTempAllowed(sha) {
                    es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
                    mgr.stateQueue.async { mgr.blockedPathToSHA[path] = sha }
                    mgr.decisionQueue.async { mgr.decisionCache[path] = .allow }
                    return
                }

                let isBlockedNow = mgr.stateQueue.sync(execute: { mgr.blockedSHAs.contains(sha) })
                if isBlockedNow {
                    // -> DENY
                    es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
                    Logfile.es.log("Denied (sync SHA): \(path)")
                    
                    mgr.stateQueue.async { mgr.blockedPathToSHA[path] = sha }
                    mgr.decisionQueue.async { mgr.decisionCache[path] = .deny }

                    // Gửi thông báo ra Terminal
                    sendTTYNotification(sha: sha)

                    DispatchQueue.global(qos: .utility).async {
                        let name = mgr.computeAppName(forExecPath: path)
                        mgr.sendBlockedNotificationToApp(name: name, path: path, sha: sha)
                    }
                    return
                } else {
                    es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
                    mgr.stateQueue.async { mgr.blockedPathToSHA[path] = sha }
                    mgr.decisionQueue.async { mgr.decisionCache[path] = .allow }
                    return
                }
            } else {
                // Read Error -> Deny
                es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
                Logfile.es.log("Failed to compute SHA -> Denying: \(path)")
                // Có thể gửi notify báo lỗi nếu muốn
                sendTTYNotification(sha: "Read-Error")
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
