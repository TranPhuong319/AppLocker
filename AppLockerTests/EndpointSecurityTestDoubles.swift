//
//  EndpointSecurityTestDoubles.swift
//  AppLockerTests
//
//  Created by Doe Phương on 4/11/26.
//

import Darwin
import EndpointSecurity
import Foundation
import os
import Testing

struct RecordedBlockedExec: Sendable, Equatable {
    let name: String
    let path: String
    let cdhash: String
    let pid: Int32
}

final class MockAuthResponder: ESAuthResponding, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private(set) var callCount: Int = 0
    private(set) var lastResult: es_auth_result_t?
    private(set) var lastCache: Bool?
    private(set) var lastMethod: ESResponseMethod?

    @discardableResult
    func respond(_ result: es_auth_result_t, cache: Bool) -> Bool {
        lock.withLock {
            callCount += 1
            lastResult = result
            lastCache = cache
            return true
        }
    }

    func recordMethod(_ method: ESResponseMethod, cache: Bool) -> es_respond_result_t {
        lock.withLock {
            callCount += 1
            lastCache = cache
            lastMethod = method
            switch method {
            case .authResult(let auth):
                lastResult = auth
            case .flagsResult(let flags):
                lastResult = (flags == 0xFFFFFFFF) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
            }
            return ES_RESPOND_RESULT_SUCCESS
        }
    }
}

final class MockESXPCNotificationSink: NSObject, ESXPCProtocol, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private(set) var blockedExecEvents: [RecordedBlockedExec] = []
    private(set) var exitedPIDs: [Int32] = []

    func notifyBlockedExec(name: String, path: String, cdhash: String, pid: Int32) {
        lock.withLock {
            blockedExecEvents.append(RecordedBlockedExec(name: name, path: path, cdhash: cdhash, pid: pid))
        }
    }

    func notifyProcessExited(pid: Int32) {
        lock.withLock { exitedPIDs.append(pid) }
    }
}

final class MockXPCNotificationDelegate: NSObject, NSXPCListenerDelegate {
    let sink: MockESXPCNotificationSink
    init(sink: MockESXPCNotificationSink) { self.sink = sink }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: ESXPCProtocol.self)
        conn.exportedObject = sink
        conn.resume()
        return true
    }
}

// MARK: - Shared Test Support & XPC Disconnect / PID Recycling Verification

enum EndpointSecurityTestSupport {
    static func realAuditToken(for pid: pid_t) -> audit_token_t? {
        var taskName: mach_port_name_t = 0
        guard task_name_for_pid(mach_task_self_, pid, &taskName) == KERN_SUCCESS else { return nil }
        defer { mach_port_deallocate(mach_task_self_, taskName) }

        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size)
        let kernRes = withUnsafeMutablePointer(to: &token) { tokenPtr in
            tokenPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(taskName, task_flavor_t(TASK_AUDIT_TOKEN), intPtr, &count)
            }
        }
        return kernRes == KERN_SUCCESS ? token : nil
    }

    static func spawnTemporarySleepProcess() throws -> (Process, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLockerESTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let sleepBin = tempDir.appendingPathComponent("sleep_test_bin")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: sleepBin)

        let proc = Process()
        proc.executableURL = sleepBin
        proc.arguments = ["15"]
        try proc.run()
        return (proc, tempDir)
    }

    static func makeClientConnection(
        endpoint: NSXPCListenerEndpoint,
        sink: MockESXPCNotificationSink
    ) -> NSXPCConnection {
        let conn = NSXPCConnection(listenerEndpoint: endpoint)
        conn.remoteObjectInterface = NSXPCInterface(with: ESAppProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: ESXPCProtocol.self)
        conn.exportedObject = sink
        conn.resume()
        return conn
    }

    static func callAllowConfigAccess(proxy: ESAppProtocol, pid: pid_t) -> Bool {
        let resultBox = OSAllocatedUnfairLock(initialState: false)
        let doneBox = OSAllocatedUnfairLock(initialState: false)
        proxy.allowConfigAccess(pid) { success in
            resultBox.withLock { $0 = success }
            doneBox.withLock { $0 = true }
        }
        let deadline = Date().addingTimeInterval(2.0)
        while !doneBox.withLock({ $0 }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return resultBox.withLock { $0 }
    }

    static func callProcessPendingApps(proxy: ESAppProtocol, approved: [Int32], rejected: [Int32]) -> Bool {
        let resultBox = OSAllocatedUnfairLock(initialState: false)
        let doneBox = OSAllocatedUnfairLock(initialState: false)
        proxy.processPendingApps(
            approvedPIDs: approved,
            rejectedPIDs: rejected,
            rejectionReason: AuthDecisionReason.userCancel.rawValue
        ) { success in
            resultBox.withLock { $0 = success }
            doneBox.withLock { $0 = true }
        }
        let deadline = Date().addingTimeInterval(2.0)
        while !doneBox.withLock({ $0 }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return resultBox.withLock { $0 }
    }
}

extension AdversarialSecurityMatrixTests {
    @Test("XPC disconnect clears authenticated PID, rejects unauthenticated commands, and blocks PID-recycled batches")
    func xpcDisconnectReauthenticationAndBatchPidRecyclingGuard() throws {
        let (childA, tempDirA) = try EndpointSecurityTestSupport.spawnTemporarySleepProcess()
        let pidA = childA.processIdentifier
        let (childB, tempDirB) = try EndpointSecurityTestSupport.spawnTemporarySleepProcess()
        let pidB = childB.processIdentifier
        defer {
            for pid in [pidA, pidB] { kill(pid, SIGKILL); kill(pid, SIGCONT) }
            childA.waitUntilExit()
            childB.waitUntilExit()
            try? FileManager.default.removeItem(at: tempDirA)
            try? FileManager.default.removeItem(at: tempDirB)
        }

        let tokenA = try #require(EndpointSecurityTestSupport.realAuditToken(for: pidA))
        var recycledTokenB = try #require(EndpointSecurityTestSupport.realAuditToken(for: pidB))
        recycledTokenB.val.7 &+= 50 // Simulate PID recycling (pidversion mismatch)
        let staleTokenB = recycledTokenB
        kill(pidA, SIGSTOP)
        kill(pidB, SIGSTOP)

        let manager = ESManager(isTesting: true)
        let uid = getuid()
        let notifA = ESManager.BlockedNotification(
            name: "ValidApp", path: "/Applications/ValidApp.app", cdhash: "a1",
            parentPid: getpid(), uid: uid, signingID: "com.test.a", targetPid: pidA
        )
        let notifB = ESManager.BlockedNotification(
            name: "RecycledApp", path: "/Applications/RecycledApp.app", cdhash: "b2",
            parentPid: getpid(), uid: uid, signingID: "com.test.b", targetPid: pidB
        )
        manager.pendingPIDLock.withLock {
            manager.pendingVerificationProcesses[pidA] = .init(
                token: tokenA, notification: notifA, registeredAt: .now - .seconds(50)
            )
            manager.pendingVerificationProcesses[pidB] = .init(
                token: staleTokenB, notification: notifB, registeredAt: .now - .seconds(50)
            )
        }

        verifyUnauthenticatedXpcCallsRejected(manager: manager, pid: pidA)
        try verifyDisconnectAndReconnectBatchProcessing(manager: manager, pidA: pidA, pidB: pidB, childB: childB)
    }

    private func verifyUnauthenticatedXpcCallsRejected(manager: ESManager, pid: pid_t) {
        var unauthReply = true
        manager.processPendingApps(approvedPIDs: [pid], rejectedPIDs: [], rejectionReason: "UserApprove") {
            unauthReply = $0
        }
        #expect(unauthReply == false)
        var unauthShutdown = true
        manager.authorizeShutdown(true) { unauthShutdown = $0 }
        #expect(unauthShutdown == false)
    }

    private func verifyDisconnectAndReconnectBatchProcessing(
        manager: ESManager, pidA: pid_t, pidB: pid_t, childB: Process
    ) throws {
        manager.customConnectionValidator = { audit_token_to_pid($0.auditToken) == getpid() }
        let listener = NSXPCListener.anonymous()
        listener.delegate = manager
        listener.resume()
        defer { listener.invalidate() }

        let sink1 = MockESXPCNotificationSink()
        let conn1 = EndpointSecurityTestSupport.makeClientConnection(endpoint: listener.endpoint, sink: sink1)
        let proxy1 = try #require(conn1.remoteObjectProxy as? ESAppProtocol)
        #expect(EndpointSecurityTestSupport.callAllowConfigAccess(proxy: proxy1, pid: getpid()) == true)
        conn1.invalidate()

        let disconnectDeadline = Date().addingTimeInterval(2.0)
        while manager.processIDLock.withLock({ manager.authenticatedMainAppPID != nil }),
              Date() < disconnectDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        #expect(manager.processIDLock.withLock { manager.authenticatedMainAppPID } == nil)
        #expect(manager.isPendingVerification(pid: pidA) == true)

        let sink2 = MockESXPCNotificationSink()
        let conn2 = EndpointSecurityTestSupport.makeClientConnection(endpoint: listener.endpoint, sink: sink2)
        defer { conn2.invalidate() }
        let proxy2 = try #require(conn2.remoteObjectProxy as? ESAppProtocol)
        #expect(EndpointSecurityTestSupport.callAllowConfigAccess(proxy: proxy2, pid: getpid()) == true)

        let renotifyDeadline = Date().addingTimeInterval(2.0)
        while sink2.blockedExecEvents.count < 2 && Date() < renotifyDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        #expect(Set(sink2.blockedExecEvents.map(\.pid)) == Set([pidA, pidB]))

        let batchResult = EndpointSecurityTestSupport.callProcessPendingApps(
            proxy: proxy2, approved: [pidA], rejected: [pidB]
        )
        #expect(batchResult == true)
        #expect(kill(pidB, 0) == 0 && childB.isRunning == true)
    }
}
