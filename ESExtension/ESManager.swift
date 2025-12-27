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

// EN: Execution decision for a process.
// VI: Quyết định thực thi cho một tiến trình.
enum ExecDecision {
    case allow
    case deny
}

// EN: Minimal, fast lock used to protect small critical sections.
// VI: Khóa tối giản, nhanh dùng để bảo vệ vùng quan trọng nhỏ.
final class FastLock {
    private var _lock = os_unfair_lock()

    /// EN: Execute closure under lock and return its value.
    /// VI: Thực thi closure dưới khóa và trả về giá trị.
    @inline(__always)
    func sync<T>(_ closure: () -> T) -> T {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return closure()
    }

    /// EN: Execute closure under lock for quick fire-and-forget writes.
    /// VI: Thực thi closure dưới khóa cho các thao tác ghi nhanh.
    @inline(__always)
    func perform(_ closure: () -> Void) {
        os_unfair_lock_lock(&_lock)
        closure()
        os_unfair_lock_unlock(&_lock)
    }
}

// EN: Errors returned by es_new_client and related setup.
// VI: Lỗi trả về từ es_new_client và quá trình thiết lập liên quan.
enum ESError: Error {
    case fullDiskAccessMissing
    case notRoot
    case entitlementMissing
    case tooManyClients
    case internalError
    case invalidArgument
    case unknown(Int32)
}

@objcMembers
final class ESManager: NSObject, NSXPCListenerDelegate {
    // EN: Static trampoline for C-style ES callbacks.
    // VI: Cầu nối tĩnh cho callback kiểu C của ES.
    static var sharedInstanceForCallbacks: ESManager?

    // EN: Published state for host app UI.
    // VI: Trạng thái công khai cho giao diện app chính.
    @Published var lockedApps: [String: LockedAppConfig] = [:]

    // EN: Endpoint Security client handle.
    // VI: Con trỏ client của Endpoint Security.
    private var client: OpaquePointer?

    // MARK: - State / Trạng thái
    // EN: Ultra-fast in-memory policy/state protected by a single lock.
    // VI: Trạng thái/chính sách trong bộ nhớ cực nhanh, bảo vệ bằng một khóa duy nhất.
    private let stateLock = FastLock()

    // EN: Block lists / mappings.
    // VI: Danh sách chặn / ánh xạ.
    private var blockedSHAs: Set<String> = []                // EN: Blocked SHA-256 digests. VI: Các SHA-256 bị khóa.
    private var blockedPathToSHA: [String: String] = [:]     // EN: Path -> SHA cache map. VI: Bản đồ cache từ đường dẫn -> SHA.

    // EN: Temporary allow windows.
    // VI: Cửa sổ cho phép tạm thời.
    private var tempAllowedSHAs: [String: Date] = [:]        // EN: SHA with expiry. VI: SHA kèm thời điểm hết hạn.
    private let allowWindowSeconds: TimeInterval = 10        // EN: Duration for one-time allow. VI: Thời lượng cho phép tạm.

    // EN: Allowed PIDs for config access.
    // VI: PID được phép truy cập cấu hình.
    private var allowedPIDs: [pid_t: Date] = [:]
    private let allowedPIDWindowSeconds: TimeInterval = 5.0

    // EN: Decision cache by path.
    // VI: Bộ nhớ đệm quyết định theo đường dẫn.
    private var decisionCache: [String: ExecDecision] = [:]

    // EN: Language settings for this process.
    // VI: Cài đặt ngôn ngữ cho tiến trình này.
    private var currentLanguage: String = Locale.preferredLanguages.first ?? "en"

    // MARK: - XPC connections / Kết nối XPC
    // EN: Manage incoming/active Mach service connections with a lightweight lock.
    // VI: Quản lý kết nối Mach service đến/đang hoạt động bằng khóa nhẹ.
    private let xpcLock = FastLock()                         // EN: Lock for connection list. VI: Khóa cho danh sách kết nối.
    private var listener: NSXPCListener?                     // EN: Mach service listener. VI: Trình lắng nghe dịch vụ Mach.
    private var activeConnections: [NSXPCConnection] = []    // EN: Active client connections. VI: Các kết nối đang hoạt động.

    // EN: Background queue for heavy I/O and hashing (not for locking state).
    // VI: Hàng đợi nền cho I/O nặng và băm (không dùng để khóa trạng thái).
    private let bgQueue = DispatchQueue(label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.bg", qos: .utility, attributes: .concurrent)

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

    // EN: App -> Extension: grant short-lived access for a PID to read config.
    // VI: App -> Extension: cấp quyền ngắn hạn cho PID đọc cấu hình.
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

    private func scheduleTempCleanup() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.cleanupTempAllowed()
            self?.scheduleTempCleanup()
        }
    }

    // EN: Fast in-place filter of expired entries under lock.
    // VI: Lọc nhanh các mục hết hạn ngay trong bộ nhớ dưới khóa.
    private func cleanupTempAllowed() {
        stateLock.perform { [weak self] in
            guard let self = self else { return }
            let now = Date()
            let countBefore = self.tempAllowedSHAs.count
            self.tempAllowedSHAs = self.tempAllowedSHAs.filter { $0.value > now }
            let removedCount = countBefore - self.tempAllowedSHAs.count
            if removedCount > 0 {
                Logfile.es.log("Temp allowed SHAs expired: \(removedCount, privacy: .public)")
            }
        }
    }

    // EN: Check if a SHA is currently allowed by a temporary window.
    // VI: Kiểm tra một SHA có đang được cho phép tạm thời hay không.
    private func isTempAllowed(_ sha: String) -> Bool {
        return stateLock.sync {
            if let expiry = tempAllowedSHAs[sha] {
                return expiry > Date()
            }
            return false
        }
    }

    // EN: Safely extract path from es_file_t pointer.
    // VI: Trích xuất đường dẫn an toàn từ con trỏ es_file_t.
    private static func safePath(fromFilePointer filePtr: UnsafePointer<es_file_t>?) -> String? {
        guard let filePtr = filePtr else { return nil }
        let file = filePtr.pointee
        if let cstr = file.path.data {
            return String(cString: cstr)
        }
        return nil
    }
}

// MARK: - Language / Ngôn ngữ
extension ESManager {
    // EN: Force the extension process to use a specific language.
    // VI: Ép tiến trình extension sử dụng ngôn ngữ cụ thể.
    @objc func updateLanguage(to code: String) {
        stateLock.perform {
            self.currentLanguage = code
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            Logfile.es.log("ES Process language forced to: \(code, privacy: .public)")
        }
    }

    // EN: Read the current language in a thread-safe way.
    // VI: Đọc ngôn ngữ hiện tại một cách an toàn luồng.
    func getCurrentLanguage() -> String {
        return stateLock.sync { self.currentLanguage }
    }
}

// MARK: - Lifecycle / Vòng đời
extension ESManager {
    // EN: Create ES client, subscribe to events, and start XPC.
    // VI: Tạo client ES, đăng ký sự kiện và khởi động XPC.
    private func start() throws {
        let res = es_new_client(&self.client) { client, message in
            ESManager.handleMessage(client: client, message: message)
        }

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

        let execEvents: [es_event_type_t] = [
            ES_EVENT_TYPE_AUTH_EXEC
        ]

        if es_subscribe(client, execEvents, UInt32(execEvents.count)) != ES_RETURN_SUCCESS {
            Logfile.es.error("es_subscribe AUTH_EXEC failed")
        }

        ESManager.sharedInstanceForCallbacks = self

        scheduleTempCleanup()
        setupMachListener()

        Logfile.es.log("ESManager started successfully")
    }

    // EN: Tear down ES client and XPC connections cleanly.
    // VI: Giải phóng client ES và các kết nối XPC một cách sạch sẽ.
    private func stop() {
        if let client { es_delete_client(client) }
        self.client = nil

        ESManager.sharedInstanceForCallbacks = nil

        listener?.delegate = nil
        listener?.invalidate()
        listener = nil

        xpcLock.perform {
            for conn in activeConnections {
                conn.invalidate()
            }
            activeConnections.removeAll()
        }

        Logfile.es.log("ESManager stopped and cleaned up")
    }
}

// MARK: - Mach service XPC / Dịch vụ Mach XPC
extension ESManager {
    // EN: Set up Mach service listener for the host app.
    // VI: Thiết lập trình lắng nghe dịch vụ Mach cho app chính.
    private func setupMachListener() {
        let l = NSXPCListener(machServiceName: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc")
        l.delegate = self
        l.resume()
        self.listener = l
        Logfile.es.log("MachService XPC listener resumed: endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc")
    }

    // EN: Try to obtain an active app connection with short backoff retries.
    // VI: Thử lấy kết nối app đang hoạt động với các lần thử và backoff ngắn.
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

    // EN: Store an incoming connection (thread-safe).
    // VI: Lưu kết nối đến (an toàn luồng).
    private func storeIncomingConnection(_ conn: NSXPCConnection) {
        xpcLock.perform {
            self.activeConnections.append(conn)
            Logfile.es.log("Stored incoming XPC connection — total=\(self.activeConnections.count, privacy: .public)")
        }
    }

    // EN: Remove a connection when it goes away.
    // VI: Gỡ kết nối khi nó kết thúc.
    private func removeIncomingConnection(_ conn: NSXPCConnection) {
        xpcLock.perform {
            self.activeConnections.removeAll { $0 === conn }
            Logfile.es.log("Removed XPC connection — total=\(self.activeConnections.count, privacy: .public)")
        }
    }

    // EN: Pick the first available active connection.
    // VI: Lấy kết nối đang hoạt động đầu tiên.
    private func pickAppConnection() -> NSXPCConnection? {
        return xpcLock.sync {
            return self.activeConnections.first
        }
    }
}

// MARK: - Blocked apps data / Dữ liệu ứng dụng bị khóa
extension ESManager {
    // EN: Notify the app when an execution is blocked.
    // VI: Gửi thông báo cho app khi một lần thực thi bị chặn.
    private func sendBlockedNotificationToApp(name: String, path: String, sha: String) {
        withRetryPickAppConnection { conn in
            guard let conn = conn else {
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
        }
    }

    // EN: Replace blocked app data with new mapping from the host app.
    // VI: Thay dữ liệu ứng dụng bị khóa bằng ánh xạ mới từ app chính.
    @objc func updateBlockedApps(_ apps: NSArray) {
        var newShas = Set<String>()
        var newPathToSha: [String: String] = [:]

        for item in apps {
            guard let dict = item as? [String: Any] ?? item as? NSDictionary as? [String: Any] else { continue }

            if let sha = dict["sha256"] as? String {
                newShas.insert(sha)
                if let path = dict["path"] as? String {
                    newPathToSha[path] = sha
                }
                Logfile.es.log("Processing update for SHA: \(sha, privacy: .public)")
            }
        }

        stateLock.perform { [weak self] in
            guard let self = self else { return }
            self.blockedSHAs = newShas
            self.blockedPathToSHA.merge(newPathToSha) { (_, new) in new }
            Logfile.es.log(
                "updateBlockedApps applied: \(newShas.count) SHAs, \(newPathToSha.count) paths"
            )
        }
    }
}

// MARK: - Temporary allow / Cho phép tạm thời
extension ESManager {
    private func allowTempSHA(_ sha: String) {
        let expiry = Date().addingTimeInterval(self.allowWindowSeconds)

        stateLock.perform { [weak self] in
            guard let self = self else { return }
            self.tempAllowedSHAs[sha] = expiry
            Logfile.es.log("Temp allowed SHA: \(sha, privacy: .public) until \(expiry, privacy: .public)")
        }
    }

    @objc func allowSHAOnce(_ sha: String, withReply reply: @escaping (Bool) -> Void) {
        allowTempSHA(sha)
        reply(true)
    }
}

// MARK: - App info / Thông tin ứng dụng
extension ESManager {
    private func computeAppName(forExecPath path: String) -> String {
        let execFile = URL(fileURLWithPath: path)
        let appBundleURL = execFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var appName = appBundleURL.deletingPathExtension().lastPathComponent
        if let bundle = Bundle(url: appBundleURL) {
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String { appName = displayName } else if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String { appName = name }
        }
        return appName
    }
}

// MARK: - TTY notifier / Thông báo TTY
final class TTYNotifier {
    /// EN: Find the TTY path of a process (e.g., /dev/ttys001).
    /// VI: Tìm đường dẫn TTY của một tiến trình (ví dụ: /dev/ttys001).
    static func getTTYPath(for pid: pid_t) -> String? {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return nil }

        let fdInfoSize = MemoryLayout<proc_fdinfo>.stride
        let numFDs = Int(bufferSize) / fdInfoSize
        var fdInfos = [proc_fdinfo](repeating: proc_fdinfo(), count: numFDs)

        let result = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdInfos, bufferSize)
        guard result > 0 else { return nil }

        for fileDescriptorInfo in fdInfos {
            // Chỉ xử lý nếu descriptor là một VNODE (tập tin/thư mục)
            if fileDescriptorInfo.proc_fdtype == PROX_FDTYPE_VNODE {
                var vnodeInfo = vnode_fdinfowithpath()
                let infoSize = Int32(MemoryLayout<vnode_fdinfowithpath>.stride)

                // Lấy thông tin chi tiết về path từ file descriptor
                let bytesReturned = proc_pidfdinfo(
                    pid,
                    fileDescriptorInfo.proc_fd,
                    PROC_PIDFDVNODEPATHINFO,
                    &vnodeInfo,
                    infoSize
                )

                if bytesReturned > 0 {
                    let path = withUnsafePointer(to: &vnodeInfo.pvip.vip_path) { pointer in
                        pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStringPointer in
                            String(cString: cStringPointer)
                        }
                    }

                    if path.hasPrefix("/dev/tty") {
                        return path
                    }
                }
            }
        }
        return nil
    }

    /// EN: Write a colored block message to the parent's TTY when execution is denied.
    /// VI: Ghi thông điệp có màu lên TTY của tiến trình cha khi bị chặn thực thi.
    static func notify(parentPid: pid_t, blockedPath: String, sha: String, identifier: String? = nil) {
        guard let ttyPath = getTTYPath(for: parentPid) else { return }
        guard let fileHandle = FileHandle(forWritingAtPath: ttyPath) else { return }
        defer { try? fileHandle.close() }

        let title        = "AppLocker"
        let description  =
        """
        The following application has been blocked from execution
        because it was added to the locked list.
        """.localized

        let labelPath    = "Path:".localized
        let labelId      = "Identifier:".localized
        let labelSha     = "SHA256:".localized
        let labelParent  = "Parent PID:".localized
        let labelAuth    = "Authenticate...".localized

        let boldRed = "\u{001B}[1m\u{001B}[31m"
        let reset   = "\u{001B}[0m"
        let bold    = "\u{001B}[1m"

        let paddedPath = labelPath.padding(toLength: 12, withPad: " ", startingAt: 0)
        let paddedId   = labelId.padding(toLength: 12, withPad: " ", startingAt: 0)
        let paddedSha  = labelSha.padding(toLength: 12, withPad: " ", startingAt: 0)
        let paddedParent = labelParent.padding(toLength: 12, withPad: " ", startingAt: 0)

        let message = """
            \n
            \(boldRed)\(title)\(reset)

            \(description)

            \(bold)\(paddedPath)\(reset) \(blockedPath)
            \(bold)\(paddedId)\(reset) \(identifier ?? "Unknown")
            \(bold)\(paddedSha)\(reset) \(sha)
            \(bold)\(paddedParent)\(reset) \(parentPid)
            \(labelAuth)
            \n
            """

        if let data = message.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
}

// MARK: - ES event handling / Xử lý sự kiện ES
extension ESManager {
    // EN: Main ES callback; currently only handles AUTH_EXEC.
    // VI: Callback ES chính; hiện chỉ xử lý AUTH_EXEC.
    private static func handleMessage(client: OpaquePointer?, message: UnsafePointer<es_message_t>?) {
        guard let client = client, let message = message else { return }
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

            let parentPid = msg.process.pointee.ppid
            var signingID = "Unsigned/Unknown"
            if let signingToken = msg.event.exec.target.pointee.signing_id.data {
                signingID = String(cString: signingToken)
            }

            // EN: Helper to deliver notifications for a deny decision.
            // VI: Trợ giúp gửi thông báo khi quyết định là chặn.
            func sendNotifications(sha: String, decision: ExecDecision) {
                if decision == .deny {
                    DispatchQueue.global(qos: .userInteractive).async {
                        TTYNotifier.notify(parentPid: parentPid, blockedPath: path, sha: sha, identifier: signingID)
                    }
                    DispatchQueue.global(qos: .utility).async {
                        let name = mgr.computeAppName(forExecPath: path)
                        mgr.sendBlockedNotificationToApp(name: name, path: path, sha: sha)
                    }
                }
            }

            // EN: Fast path — single lock read of all state.
            // VI: Đường nhanh — đọc toàn bộ trạng thái trong một lần khóa.
            let decisionResult: ExecDecision? = mgr.stateLock.sync {
                if let mappedSHA = mgr.blockedPathToSHA[path] {
                    if let expiry = mgr.tempAllowedSHAs[mappedSHA], expiry > Date() {
                        return .allow
                    }
                    if mgr.blockedSHAs.contains(mappedSHA) {
                        return .deny
                    }
                }
                if let cached = mgr.decisionCache[path] {
                    return cached
                }
                return nil
            }

            if let decision = decisionResult {
                let authResult = (decision == .allow) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
                es_respond_auth_result(client, message, authResult, false)

                if decision == .deny {
                    Logfile.es.log("Denied by FastPath (Cache/Map): \(path, privacy: .public)")
                    let shaForNotify = mgr.stateLock.sync { mgr.blockedPathToSHA[path] ?? "Cached-No-SHA" }
                    sendNotifications(sha: shaForNotify, decision: .deny)
                }
                return
            }

            // EN: Slow path — compute SHA outside the lock.
            // VI: Đường chậm — tính SHA ngoài khóa.
            if let sha = computeSHA(forPath: path) {
                let finalDecision: ExecDecision = mgr.stateLock.sync {
                    if let expiry = mgr.tempAllowedSHAs[sha], expiry > Date() {
                        return .allow
                    }
                    return mgr.blockedSHAs.contains(sha) ? .deny : .allow
                }

                mgr.stateLock.perform {
                    mgr.blockedPathToSHA[path] = sha
                    mgr.decisionCache[path] = finalDecision
                }

                let authResult = (finalDecision == .allow) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
                es_respond_auth_result(client, message, authResult, false)

                if finalDecision == .deny {
                    Logfile.es.log("Denied by SlowPath (SHA): \(path, privacy: .public)")
                    sendNotifications(sha: sha, decision: .deny)
                }
                return

            } else {
                es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
                Logfile.es.log("Failed to compute SHA -> Denying: \(path, privacy: .public)")
                sendNotifications(sha: "Read-Error", decision: .deny)
                return
            }
        }
    }
}

// MARK: - NSXPCListenerDelegate / Đại biểu NSXPCListener
extension ESManager {
    // EN: Accept and manage incoming XPC connections from the app.
    // VI: Chấp nhận và quản lý các kết nối XPC đến từ ứng dụng.
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
