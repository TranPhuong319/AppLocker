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
        defer { connection.invalidate(); listener.invalidate() }

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
        defer { connection.invalidate(); listener.invalidate() }

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

        let coordinator = makeTestCoordinator(defaults: defaults)
        var batchWindowShown = false
        var cancelCalledCount = 0

        coordinator.dependencies.isBatchWindowVisible = { batchWindowShown }
        coordinator.dependencies.showBatchWindow = { batchWindowShown = true }
        coordinator.dependencies.hideBatchWindow = { batchWindowShown = false }
        coordinator.dependencies.cancelAuth = { cancelCalledCount += 1 }

        coordinator.addPendingAuth(name: "Safari", path: "/Applications/Safari.app", cdhash: "hash1", pid: 1001)
        let singleAuthCont = await coordinator.waitForAuthStart {
            coordinator.processIncomingQueue()
        }
        #expect(coordinator.isAuthenticatingSingleApp == true)
        #expect(coordinator.currentSingleAppPID == 1001)

        coordinator.addPendingAuth(name: "Notes", path: "/System/Applications/Notes.app", cdhash: "hash2", pid: 1002)
        #expect(coordinator.isUpgradingToBatch == true)
        #expect(cancelCalledCount == 1)

        await withCheckedContinuation { cont in
            coordinator.dependencies.showBatchWindow = {
                batchWindowShown = true
                cont.resume()
            }
            singleAuthCont.resume(returning: false)
        }
        #expect(batchWindowShown == true)
        #expect(coordinator.pendingApps.count == 2)

        coordinator.pendingApps[1].isSelected = false
        coordinator.dependencies.authenticate = { _ in true }
        let decision1 = await coordinator.waitForDecision {
            coordinator.handleAuthenticate()
        }
        #expect(batchWindowShown == false)
        #expect(decision1.approved == [1001])
        #expect(decision1.rejected == [1002])
        #expect(decision1.reason == AuthDecisionReason.userCancel.rawValue)

        let decision2 = await coordinator.waitForDecision {
            coordinator.addPendingAuth(name: "Music", path: "/Applications/Music.app", cdhash: "hash3", pid: 1003)
            coordinator.handleCancel(reason: AuthDecisionReason.userCancel.rawValue)
        }
        #expect(decision2.approved == [])
        #expect(decision2.rejected == [1003])
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

        let coordinator = makeTestCoordinator(defaults: defaults)
        var notifiedApps: [String] = []

        coordinator.dependencies.sendBlockedNotification = { notifiedApps.append($0) }

        // 1. Notification enabled (default) + Single App Approved
        coordinator.dependencies.authenticate = { _ in true }
        let decision1 = await coordinator.waitForDecision {
            coordinator.addPendingAuth(name: "Zalo", path: "/Applications/Zalo.app", cdhash: "zalo_hash", pid: 2001)
            coordinator.processIncomingQueue()
        }

        #expect(notifiedApps == ["Zalo"])
        #expect(decision1.approved == [2001])
        #expect(decision1.rejected == [])
        #expect(decision1.reason == AuthDecisionReason.userApprove.rawValue)
        #expect(coordinator.lastAuthTimestampsByPath["/Applications/Zalo.app"] != nil)

        // 2. Notification disabled + LAError.userCancel -> UserCancel reason
        defaults.set(false, forKey: "showBlockedNotifications")
        coordinator.dependencies.authenticate = { _ in throw LAError(.userCancel) }
        let decision2 = await coordinator.waitForDecision {
            coordinator.addPendingAuth(name: "Photos", path: "/Applications/Photos.app", cdhash: "ph1", pid: 2002)
            coordinator.processIncomingQueue()
        }

        #expect(notifiedApps == ["Zalo"])
        #expect(decision2.approved == [])
        #expect(decision2.rejected == [2002])
        #expect(decision2.reason == AuthDecisionReason.userCancel.rawValue)

        // 3. LAError.appCancel -> Timeout reason
        coordinator.dependencies.authenticate = { _ in throw LAError(.appCancel) }
        let decision3 = await coordinator.waitForDecision {
            coordinator.addPendingAuth(name: "Phone", path: "/Applications/Phone.app", cdhash: "ph2", pid: 2003)
            coordinator.processIncomingQueue()
        }

        #expect(decision3.approved == [])
        #expect(decision3.rejected == [2003])
        #expect(decision3.reason == AuthDecisionReason.timeout.rawValue)
    }

    @Test("Process exit during single or batch auth cancels LAContext and hides batch window when empty")
    @MainActor
    func processExitCleanupCancelsAuthAndHidesWindow() async throws {
        let coordinator = makeTestCoordinator()
        var cancelCount = 0
        var hideWindowCount = 0

        coordinator.dependencies.cancelAuth = { cancelCount += 1 }
        coordinator.dependencies.hideBatchWindow = { hideWindowCount += 1 }

        // 1. Single app exits while Touch ID prompt is active
        coordinator.addPendingAuth(name: "Zalo", path: "/Applications/Zalo.app", cdhash: "h1", pid: 3001)
        let authCont = await coordinator.waitForAuthStart {
            coordinator.processIncomingQueue()
        }
        #expect(coordinator.isAuthenticatingSingleApp == true)

        coordinator.removePendingProcess(pid: 3001)
        #expect(coordinator.isAuthenticatingSingleApp == false)
        #expect(cancelCount == 1)
        #expect(hideWindowCount == 1)
        authCont.resume(returning: false)
        await Task.yield()

        // 2. Batch apps exit one by one -> window hides only when last process exits
        coordinator.addPendingAuth(name: "App1", path: "/Applications/App1.app", cdhash: "h2", pid: 3002)
        coordinator.addPendingAuth(name: "App2", path: "/Applications/App2.app", cdhash: "h3", pid: 3003)
        coordinator.processIncomingQueue()

        coordinator.removePendingProcess(pid: 3002)
        #expect(coordinator.pendingApps.map(\.pid) == [3003])
        #expect(hideWindowCount == 1)

        coordinator.removePendingProcess(pid: 3003)
        #expect(coordinator.pendingApps.isEmpty)
        #expect(hideWindowCount == 2)
    }

    @Test("New app arriving during active batch Touch ID merges into batch and auto re-authenticates")
    @MainActor
    func batchMidAuthArrivalMergesAndReAuthenticates() async throws {
        let coordinator = makeTestCoordinator()
        var cancelCount = 0

        coordinator.dependencies.cancelAuth = { cancelCount += 1 }

        coordinator.addPendingAuth(name: "Zalo", path: "/Applications/Zalo.app", cdhash: "h1", pid: 4001)
        coordinator.addPendingAuth(name: "Photos", path: "/Applications/Photos.app", cdhash: "h2", pid: 4002)
        let firstBatchCont = await coordinator.waitForAuthStart {
            coordinator.handleAuthenticate()
        }
        #expect(coordinator.isAuthenticatingBatch == true)

        // 3rd app arrives while batch Touch ID is on screen
        coordinator.addPendingAuth(name: "Phone", path: "/Applications/Phone.app", cdhash: "h3", pid: 4003)
        #expect(coordinator.isRestartingBatchWithNewApps == true)
        #expect(cancelCount == 1)

        let decision = await coordinator.waitForDecision {
            coordinator.dependencies.authenticate = { _ in true }
            firstBatchCont.resume(throwing: LAError(.appCancel))
        }

        #expect(decision.approved == [4001, 4002, 4003])
        #expect(decision.rejected == [])
    }

    @Test("Grace period allows immediate relaunch without re-prompting Touch ID")
    @MainActor
    func gracePeriodAutoApprovesRelaunch() async throws {
        let originalTimeout = LockES.shared.autoLockTimeoutMinutes
        LockES.shared.autoLockTimeoutMinutes = 5
        defer { LockES.shared.autoLockTimeoutMinutes = originalTimeout }

        let coordinator = makeTestCoordinator()
        var approvedPIDs: [Int32] = []
        coordinator.dependencies.processPendingApps = { approved, _, _ in
            approvedPIDs.append(contentsOf: approved)
        }

        coordinator.lastAuthTimestampsByPath["/Applications/Zalo.app"] = Date()
        coordinator.addPendingAuth(name: "Zalo", path: "/Applications/Zalo.app", cdhash: "hash_zalo", pid: 5001)
        #expect(approvedPIDs == [5001])
        #expect(coordinator.pendingApps.isEmpty)

        coordinator.addPendingAuth(name: "Photos", path: "/System/Applications/Photos.app", cdhash: "hash_p", pid: 5002)
        #expect(coordinator.pendingApps.map(\.pid) == [5002])
    }

    @Test("Single app auth cancellation does not emit duplicate rejection on delayed completion")
    @MainActor
    func singleAppCancelDoesNotEmitDuplicateRejection() async throws {
        let coordinator = makeTestCoordinator()
        var duplicateDecisions: [RecordedBatchDecision] = []

        coordinator.addPendingAuth(name: "Notes", path: "/Applications/Notes.app", cdhash: "h_notes", pid: 6001)
        let authCont = await coordinator.waitForAuthStart {
            coordinator.processIncomingQueue()
        }
        #expect(coordinator.isAuthenticatingSingleApp == true)

        let decision = await coordinator.waitForDecision {
            coordinator.handleCancel(reason: AuthDecisionReason.userCancel.rawValue)
        }
        #expect(decision.rejected == [6001])

        coordinator.dependencies.processPendingApps = { approved, rejected, reason in
            duplicateDecisions.append(RecordedBatchDecision(approved: approved, rejected: rejected, reason: reason))
        }
        authCont.resume(throwing: LAError(.userCancel))
        await Task.yield()
        #expect(duplicateDecisions.isEmpty)
    }

    @Test("XPCServer forwards incoming notifications to AuthCoordinator")
    @MainActor
    func xpcServerForwardsNotificationsToAuthCoordinator() async throws {
        let server = XPCServer.shared
        let originalProtection = LockES.shared.isProtectionDisabled
        LockES.shared.isProtectionDisabled = false
        defer {
            LockES.shared.isProtectionDisabled = originalProtection
            AuthCoordinator.shared.removePendingProcess(pid: 7001)
        }

        server.notifyBlockedExec(name: "Safari", path: "/Applications/Safari.app", cdhash: "test_hash", pid: 7001)
        while !AuthCoordinator.shared.pendingApps.contains(where: { $0.pid == 7001 }) {
            await Task.yield()
        }
        #expect(AuthCoordinator.shared.pendingApps.contains(where: { $0.pid == 7001 }))

        server.notifyProcessExited(pid: 7001)
        while AuthCoordinator.shared.pendingApps.contains(where: { $0.pid == 7001 }) {
            await Task.yield()
        }
        #expect(!AuthCoordinator.shared.pendingApps.contains(where: { $0.pid == 7001 }))
    }
}

@MainActor
private func makeTestCoordinator(defaults: UserDefaults? = nil) -> AuthCoordinator {
    let coordinator = AuthCoordinator()
    if let defaults { coordinator.dependencies.userDefaults = defaults }
    coordinator.dependencies.isBatchWindowVisible = { false }
    coordinator.dependencies.showBatchWindow = {}
    coordinator.dependencies.hideBatchWindow = {}
    coordinator.dependencies.sendBlockedNotification = { _ in }
    coordinator.dependencies.cancelAuth = {}
    coordinator.dependencies.refreshWatchdog = { _ in }
    coordinator.dependencies.processPendingApps = { _, _, _ in }
    coordinator.dependencies.sleep = {
        if $0 < .seconds(1) { await Task.yield() } else { try await Task.sleep(for: $0) }
    }
    return coordinator
}

@MainActor
private extension AuthCoordinator {
    func waitForDecision(action: () -> Void) async -> RecordedBatchDecision {
        await withCheckedContinuation { cont in
            self.dependencies.processPendingApps = { approved, rejected, reason in
                cont.resume(returning: RecordedBatchDecision(approved: approved, rejected: rejected, reason: reason))
            }
            action()
        }
    }

    func waitForAuthStart(action: () -> Void) async -> CheckedContinuation<Bool, Error> {
        await withCheckedContinuation { cont in
            self.dependencies.authenticate = { _ in
                try await withCheckedThrowingContinuation { authCont in
                    cont.resume(returning: authCont)
                }
            }
            action()
        }
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
