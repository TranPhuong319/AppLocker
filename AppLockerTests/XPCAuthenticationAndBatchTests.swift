//
//  XPCAuthenticationAndBatchTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 4/11/26.
//

import Darwin
import Foundation
import LocalAuthentication
import os
import Testing

struct RecordedBatchDecision: Sendable, Equatable {
    let approved: [Int32]
    let rejected: [Int32]
    let reason: String
}

@Suite("Anonymous NSXPCListener Handshake, Anti-Spoofing & Batch Auth Queue Tests", .serialized)
struct XPCAuthenticationAndBatchTests {

    @Test("Anonymous NSXPCListener connects client to ESManager(isTesting: true) and executes ESAppProtocol")
    func anonymousXpcListenerHandshakeAndAppProtocolRequests() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLockerXPCTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ESManager(isTesting: true, baseConfigDirectoryURL: tempDir)
        manager.customConnectionValidator = { audit_token_to_pid($0.auditToken) == getpid() }
        let listener = NSXPCListener.anonymous()
        listener.delegate = manager
        listener.resume()

        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: ESAppProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: ESXPCProtocol.self)
        connection.exportedObject = MockESXPCNotificationSink()
        connection.resume()
        defer {
            connection.invalidate()
            listener.invalidate()
        }

        let proxy = try #require(connection.remoteObjectProxy as? ESAppProtocol)
        #expect(callAllowConfigAccess(proxy: proxy, pid: getpid()) == true)
        #expect(manager.processIDLock.withLock { manager.authenticatedMainAppPID } == getpid())

        proxy.updateIncomingCallRingingState(true)
        let callDeadline = Date().addingTimeInterval(1.0)
        while !manager.stateLock.withLock({ manager.isIncomingCallActive }) && Date() < callDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        #expect(manager.stateLock.withLock { manager.isIncomingCallActive } == true)

        // Simulate PID-recycling / PIDversion mismatch on existing XPC connection
        manager.processIDLock.withLock {
            manager.authenticatedMainAppPIDVersion = (manager.authenticatedMainAppPIDVersion ?? 0) &+ 1
        }
        #expect(callAllowConfigAccess(proxy: proxy, pid: getpid()) == false)
    }

    private func callAllowConfigAccess(proxy: ESAppProtocol, pid: pid_t) -> Bool {
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

    @Test("XPC listener rejects connection when customConnectionValidator denies signature")
    func xpcConnectionRejectedWhenSignatureValidatorFails() {
        let manager = ESManager(isTesting: true)
        manager.customConnectionValidator = { _ in false }

        let listener = NSXPCListener.anonymous()
        listener.delegate = manager
        listener.resume()

        let errorBox = OSAllocatedUnfairLock(initialState: false)
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: ESAppProtocol.self)
        connection.resumeAndExpectError(errorBox: errorBox)
        defer {
            connection.invalidate()
            listener.invalidate()
        }

        let deadline = Date().addingTimeInterval(2.0)
        while !errorBox.withLock({ $0 }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        #expect(errorBox.withLock { $0 } == true)
    }

    @Test("Batch authentication queue groups multiple apps, upgrades single prompt, and handles selective approval")
    @MainActor
    func batchAuthQueueUpgradeAndSelectiveApproval() async throws {
        let suiteName = "com.TranPhuong319.BatchTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let server = XPCServer()
        server.dependencies.userDefaults = defaults

        var batchWindowShown = false
        var cancelCalledCount = 0
        var processedBatches: [RecordedBatchDecision] = []

        server.dependencies.isBatchWindowVisible = { batchWindowShown }
        server.dependencies.onShowBatchWindow = { batchWindowShown = true }
        server.dependencies.onHideBatchWindow = { batchWindowShown = false }
        server.dependencies.cancelAuth = { cancelCalledCount += 1 }
        server.dependencies.onRefreshWatchdog = { _ in }
        server.dependencies.onProcessPendingApps = { approved, rejected, reason in
            processedBatches.append(RecordedBatchDecision(approved: approved, rejected: rejected, reason: reason))
        }

        var singleAuthContinuation: CheckedContinuation<Bool, Error>?
        server.dependencies.authenticate = { _ in
            try await withCheckedThrowingContinuation { cont in
                singleAuthContinuation = cont
            }
        }

        server.addPendingAuth(name: "Safari", path: "/Applications/Safari.app", cdhash: "hash1", pid: 1001)
        server.processIncomingQueue()
        #expect(server.isAuthenticatingSingleApp == true)
        #expect(server.currentSingleAppPID == 1001)
        try await Task.sleep(for: .milliseconds(20))

        server.addPendingAuth(name: "Notes", path: "/System/Applications/Notes.app", cdhash: "hash2", pid: 1002)
        #expect(server.isUpgradingToBatch == true)
        #expect(cancelCalledCount == 1)

        singleAuthContinuation?.resume(returning: false)
        try await Task.sleep(for: .milliseconds(50))

        #expect(batchWindowShown == true)
        #expect(server.pendingApps.count == 2)

        server.pendingApps[1].isSelected = false
        server.dependencies.authenticate = { _ in true }

        server.handleAuthenticate()
        try await Task.sleep(for: .milliseconds(50))

        #expect(batchWindowShown == false)
        #expect(processedBatches.count == 1)
        #expect(processedBatches.first?.approved == [1001])
        #expect(processedBatches.first?.rejected == [1002])
        #expect(processedBatches.first?.reason == AuthDecisionReason.userCancel.rawValue)

        server.addPendingAuth(name: "Music", path: "/System/Applications/Music.app", cdhash: "hash3", pid: 1003)
        server.handleCancel(reason: AuthDecisionReason.userCancel.rawValue)
        #expect(processedBatches.count == 2)
        #expect(processedBatches.last?.approved == [])
        #expect(processedBatches.last?.rejected == [1003])
    }
}

// MARK: - Single Auth, Process Exit & Grace Period Tests

extension XPCAuthenticationAndBatchTests {
    @Test("Single app authentication handles approval, userCancel, appCancel timeout, and notification toggle")
    @MainActor
    func singleAppAuthDecisionsAndNotificationToggle() async throws {
        let suiteName = "com.TranPhuong319.SingleAuthTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let server = XPCServer()
        server.dependencies.userDefaults = defaults

        var notifiedApps: [String] = []
        var decisions: [RecordedBatchDecision] = []

        server.dependencies.onSendBlockedNotification = { notifiedApps.append($0) }
        server.dependencies.onProcessPendingApps = { approved, rejected, reason in
            decisions.append(RecordedBatchDecision(approved: approved, rejected: rejected, reason: reason))
        }

        // 1. Notification enabled (default) + Single App Approved
        server.dependencies.authenticate = { _ in true }
        server.addPendingAuth(name: "Zalo", path: "/Applications/Zalo.app", cdhash: "zalo_hash", pid: 2001)
        server.processIncomingQueue()
        try await Task.sleep(for: .milliseconds(40))

        #expect(notifiedApps == ["Zalo"])
        #expect(decisions.last?.approved == [2001])
        #expect(decisions.last?.rejected == [])
        #expect(decisions.last?.reason == AuthDecisionReason.userApprove.rawValue)
        #expect(server.lastAuthTimestampsByPath["/Applications/Zalo.app"] != nil)

        // 2. Notification disabled + LAError.userCancel -> UserCancel reason
        defaults.set(false, forKey: "showBlockedNotifications")
        server.dependencies.authenticate = { _ in throw LAError(.userCancel) }
        server.addPendingAuth(name: "Photos", path: "/System/Applications/Photos.app", cdhash: "photos_hash", pid: 2002)
        server.processIncomingQueue()
        try await Task.sleep(for: .milliseconds(40))

        #expect(notifiedApps == ["Zalo"])
        #expect(decisions.last?.approved == [])
        #expect(decisions.last?.rejected == [2002])
        #expect(decisions.last?.reason == AuthDecisionReason.userCancel.rawValue)

        // 3. LAError.appCancel -> Timeout reason
        server.dependencies.authenticate = { _ in throw LAError(.appCancel) }
        server.addPendingAuth(name: "Phone", path: "/System/Applications/Phone.app", cdhash: "phone_hash", pid: 2003)
        server.processIncomingQueue()
        try await Task.sleep(for: .milliseconds(40))

        #expect(decisions.last?.approved == [])
        #expect(decisions.last?.rejected == [2003])
        #expect(decisions.last?.reason == AuthDecisionReason.timeout.rawValue)
    }

    @Test("Process exit during single or batch auth cancels LAContext and hides batch window when empty")
    @MainActor
    func processExitCleanupCancelsAuthAndHidesWindow() async throws {
        let server = XPCServer()
        var cancelCount = 0
        var hideWindowCount = 0

        server.dependencies.cancelAuth = { cancelCount += 1 }
        server.dependencies.onHideBatchWindow = { hideWindowCount += 1 }
        server.dependencies.onRefreshWatchdog = { _ in }

        var authContinuation: CheckedContinuation<Bool, Error>?
        server.dependencies.authenticate = { _ in
            try await withCheckedThrowingContinuation { cont in
                authContinuation = cont
            }
        }

        // 1. Single app exits while Touch ID prompt is active
        server.addPendingAuth(name: "Zalo", path: "/Applications/Zalo.app", cdhash: "h1", pid: 3001)
        server.processIncomingQueue()
        try await Task.sleep(for: .milliseconds(20))
        #expect(server.isAuthenticatingSingleApp == true)

        server.removePendingProcess(pid: 3001)
        #expect(server.isAuthenticatingSingleApp == false)
        #expect(cancelCount == 1)
        #expect(hideWindowCount == 1)
        authContinuation?.resume(returning: false)
        try await Task.sleep(for: .milliseconds(20))

        // 2. Batch apps exit one by one -> window hides only when last process exits
        server.addPendingAuth(name: "App1", path: "/Applications/App1.app", cdhash: "h2", pid: 3002)
        server.addPendingAuth(name: "App2", path: "/Applications/App2.app", cdhash: "h3", pid: 3003)
        server.processIncomingQueue()

        server.removePendingProcess(pid: 3002)
        #expect(server.pendingApps.map(\.pid) == [3003])
        #expect(hideWindowCount == 1)

        server.removePendingProcess(pid: 3003)
        #expect(server.pendingApps.isEmpty)
        #expect(hideWindowCount == 2)
    }

    @Test("New app arriving during active batch Touch ID merges into batch and auto re-authenticates")
    @MainActor
    func batchMidAuthArrivalMergesAndReAuthenticates() async throws {
        let server = XPCServer()
        var cancelCount = 0
        var decisions: [RecordedBatchDecision] = []

        server.dependencies.cancelAuth = { cancelCount += 1 }
        server.dependencies.onRefreshWatchdog = { _ in }
        server.dependencies.onHideBatchWindow = {}
        server.dependencies.onProcessPendingApps = { approved, rejected, reason in
            decisions.append(RecordedBatchDecision(approved: approved, rejected: rejected, reason: reason))
        }

        var firstBatchContinuation: CheckedContinuation<Bool, Error>?
        var attempt = 0
        server.dependencies.authenticate = { _ in
            attempt += 1
            if attempt == 1 {
                return try await withCheckedThrowingContinuation { cont in
                    firstBatchContinuation = cont
                }
            }
            return true
        }

        server.addPendingAuth(name: "Zalo", path: "/Applications/Zalo.app", cdhash: "h1", pid: 4001)
        server.addPendingAuth(name: "Photos", path: "/System/Applications/Photos.app", cdhash: "h2", pid: 4002)
        server.handleAuthenticate()
        try await Task.sleep(for: .milliseconds(20))
        #expect(server.isAuthenticatingBatch == true)

        // 3rd app arrives while batch Touch ID is on screen
        server.addPendingAuth(name: "Phone", path: "/System/Applications/Phone.app", cdhash: "h3", pid: 4003)
        #expect(server.isRestartingBatchWithNewApps == true)
        #expect(cancelCount == 1)

        // First LAContext finishes with cancellation -> auto re-authenticates after 250ms with all 3 apps
        firstBatchContinuation?.resume(throwing: LAError(.appCancel))
        try await Task.sleep(for: .milliseconds(350))

        #expect(attempt == 2)
        #expect(decisions.count == 1)
        #expect(decisions.first?.approved == [4001, 4002, 4003])
        #expect(decisions.first?.rejected == [])
    }

    @Test("Grace period allows immediate relaunch without re-prompting Touch ID")
    @MainActor
    func gracePeriodAutoApprovesRelaunch() async throws {
        let originalTimeout = LockES.shared.autoLockTimeoutMinutes
        LockES.shared.autoLockTimeoutMinutes = 5
        defer { LockES.shared.autoLockTimeoutMinutes = originalTimeout }

        let server = XPCServer()
        var approvedPIDs: [Int32] = []
        server.dependencies.onProcessPendingApps = { approved, _, _ in
            approvedPIDs.append(contentsOf: approved)
        }

        // Simulate successful initial auth
        server.lastAuthTimestampsByPath["/Applications/Zalo.app"] = Date()

        // 1. Relaunch within grace period -> auto-approves immediately without adding to pendingApps
        server.addPendingAuth(name: "Zalo", path: "/Applications/Zalo.app", cdhash: "hash_zalo", pid: 5001)

        #expect(approvedPIDs == [5001])
        #expect(server.pendingApps.isEmpty)

        // 2. Different app not in grace period -> added to pendingApps
        server.addPendingAuth(name: "Photos", path: "/System/Applications/Photos.app", cdhash: "hash_photos", pid: 5002)
        #expect(server.pendingApps.map(\.pid) == [5002])
    }
}

private extension NSXPCConnection {
    func resumeAndExpectError(errorBox: OSAllocatedUnfairLock<Bool>) {
        self.resume()
        let proxy = self.remoteObjectProxyWithErrorHandler { _ in
            errorBox.withLock { $0 = true }
        } as? ESAppProtocol
        proxy?.allowConfigAccess(getpid()) { _ in }
    }
}
