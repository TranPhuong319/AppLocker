//
//  ResilienceAndStoreCoverageTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 28/11/26.
//

import Darwin
import Foundation
import os
import Testing

// MARK: - 1. ESEventNotifyExit (Guardian) & ESManager+Auth Tests

@Suite("Guardian Exit Watchdog & ESManager Auth XPC Tests", .serialized)
struct GuardianExitAndAuthTests {
    @Test("Pending process exit removes record and notifies main app over XPC")
    func pendingExitNotifiesMainApp() async throws {
        let manager = ESManager(isTesting: true)
        manager.customConnectionValidator = { audit_token_to_pid($0.auditToken) == getpid() }
        let listener = NSXPCListener.anonymous()
        listener.delegate = manager
        listener.resume()
        defer { listener.invalidate() }

        let sink = MockESXPCNotificationSink()
        let conn = EndpointSecurityTestSupport.makeClientConnection(endpoint: listener.endpoint, sink: sink)
        defer { conn.invalidate() }

        let proxy = try #require(conn.remoteObjectProxy as? ESAppProtocol)
        #expect(EndpointSecurityTestSupport.callAllowConfigAccess(proxy: proxy, pid: getpid()) == true)

        let pendingPID: pid_t = 44556
        let token = try #require(ESManager.auditToken(for: getpid()))
        let note = ESManager.BlockedNotification(
            name: "Demo", path: "/Applications/Demo.app", cdhash: "abcd",
            parentPid: getpid(), uid: audit_token_to_euid(token), signingID: "com.demo.app", targetPid: pendingPID
        )
        manager.markPendingVerification(pid: pendingPID, token: token, notification: note)
        manager.evaluateNotifyExit(context: ExitEventContext(
            exitingPID: pendingPID, exitingUID: audit_token_to_euid(token), isMainApp: false, exitStat: 0
        ))

        #expect(manager.isPendingVerification(pid: pendingPID) == false)
        try await waitAsync { sink.exitedPIDs.contains(pendingPID) }
        #expect(sink.exitedPIDs.contains(pendingPID))
    }

    @Test("Main app clean exit (stat 0) clears PIDs without invoking Guardian restarter")
    func mainAppCleanExitDoesNotRestartAgent() async throws {
        let manager = ESManager(isTesting: true)
        let restartCount = OSAllocatedUnfairLock(initialState: 0)
        manager.guardianWatchdogDelay = .milliseconds(15)
        manager.guardianAgentRestarter = { _ in restartCount.withLock { $0 += 1 } }
        manager.stateLock.withLock { manager.activeUserUID = 501 }
        manager.processIDLock.withLock {
            manager.authenticatedMainAppPID = 9001
            manager.authenticatedMainAppPIDVersion = 7
            manager.lastKnownMainAppPID = 9001
        }

        manager.evaluateNotifyExit(context: ExitEventContext(
            exitingPID: 9001, exitingUID: 501, isMainApp: true, exitStat: 0
        ))
        try await Task.sleep(for: .milliseconds(50))
        #expect(manager.processIDLock.withLock { manager.authenticatedMainAppPID } == nil)
        #expect(manager.processIDLock.withLock { manager.lastKnownMainAppPID } == nil)
        #expect(restartCount.withLock { $0 } == 0)
    }

    @Test("Main app crash (stat != 0) triggers Guardian restarter unless app recovers in time")
    func mainAppCrashRecoveryAndCancellation() async throws {
        let manager = ESManager(isTesting: true)
        let restartedUIDs = OSAllocatedUnfairLock(initialState: [uid_t]())
        manager.guardianWatchdogDelay = .milliseconds(25)
        manager.guardianAgentRestarter = { uid in restartedUIDs.withLock { $0.append(uid) } }
        manager.stateLock.withLock { manager.activeUserUID = 501 }
        manager.processIDLock.withLock {
            manager.authenticatedMainAppPID = 9002
            manager.lastKnownMainAppPID = 9002
        }
        manager.evaluateNotifyExit(context: ExitEventContext(
            exitingPID: 9002, exitingUID: 501, isMainApp: true, exitStat: 9
        ))
        try await waitAsync { !restartedUIDs.withLock { $0.isEmpty } }
        #expect(restartedUIDs.withLock { $0 } == [501])

        manager.processIDLock.withLock { manager.authenticatedMainAppPID = 9003 }
        manager.evaluateNotifyExit(context: ExitEventContext(
            exitingPID: 9003, exitingUID: 501, isMainApp: true, exitStat: 9
        ))
        manager.processIDLock.withLock { manager.authenticatedMainAppPID = 9004 }
        try await Task.sleep(for: .milliseconds(60))
        #expect(restartedUIDs.withLock { $0 } == [501])
    }

    @Test("ESManager+Auth refreshes pending watchdog and rejects unauthenticated requests")
    func refreshWatchdogAndRejectUnauthenticated() async throws {
        let manager = ESManager(isTesting: true)
        manager.customConnectionValidator = { audit_token_to_pid($0.auditToken) == getpid() }
        let listener = NSXPCListener.anonymous()
        listener.delegate = manager
        listener.resume()
        defer { listener.invalidate() }

        let conn = EndpointSecurityTestSupport.makeClientConnection(
            endpoint: listener.endpoint, sink: MockESXPCNotificationSink()
        )
        defer { conn.invalidate() }
        let proxy = try #require(conn.remoteObjectProxy as? ESAppProtocol)
        #expect(EndpointSecurityTestSupport.callAllowConfigAccess(proxy: proxy, pid: getpid()) == true)

        // Simulate PID-recycling / unauthenticated connection before invoking ESManager+Auth methods
        let savedVersion = manager.processIDLock.withLock { () -> Int32? in
            let current = manager.authenticatedMainAppPIDVersion
            manager.authenticatedMainAppPIDVersion = (current ?? 0) &+ 1
            return current
        }
        proxy.updateIncomingCallRingingState(true)
        proxy.refreshPendingWatchdog(pids: [5555])
        try await Task.sleep(for: .milliseconds(30))
        #expect(manager.stateLock.withLock { manager.isIncomingCallActive } == false)

        manager.processIDLock.withLock { manager.authenticatedMainAppPIDVersion = savedVersion }
        let token = try #require(ESManager.auditToken(for: getpid()))
        let staleTime = ContinuousClock.now - .seconds(60)
        manager.pendingPIDLock.withLock {
            manager.pendingVerificationProcesses[5555] = ESManager.PendingProcessRecord(
                token: token,
                notification: ESManager.BlockedNotification(
                    name: "Test", path: "/Applications/Test.app", cdhash: "00",
                    parentPid: 1, uid: 501, signingID: "com.test", targetPid: 5555
                ),
                registeredAt: staleTime
            )
        }

        proxy.refreshPendingWatchdog(pids: [5555, 0, -1])
        try await waitAsync {
            let updated = manager.pendingPIDLock.withLock { manager.pendingVerificationProcesses[5555]?.registeredAt }
            return updated.map { $0 > staleTime } ?? false
        }
        let updatedAt = manager.pendingPIDLock.withLock { manager.pendingVerificationProcesses[5555]?.registeredAt }
        #expect((updatedAt ?? staleTime) > staleTime)
    }
}

// MARK: - 2. ESXPCClient+Requests Tests

@Suite("ESXPCClient Requests & Retry Guard Tests", .serialized)
struct ESXPCClientRequestsTests {
    @Test("ESXPCClient+Requests sends allowConfigAccess, processPendingApps, and updateLanguage")
    func xpcRequestsSucceedOverLiveConnection() async throws {
        let manager = ESManager(isTesting: true)
        manager.customConnectionValidator = { audit_token_to_pid($0.auditToken) == getpid() }
        let listener = NSXPCListener.anonymous()
        listener.delegate = manager
        listener.resume()
        defer { listener.invalidate() }
        let endpoint = listener.endpoint

        let connected = OSAllocatedUnfairLock(initialState: false)
        let client = makeClient(endpoint: endpoint, isInstalled: true) { connected.withLock { $0 = true } }
        defer { client.disconnect() }
        client.connect()
        try await waitAsync { connected.withLock { $0 } }

        let accessOK = await withCheckedContinuation { cont in
            client.allowConfigAccess(getpid()) { cont.resume(returning: $0) }
        }
        #expect(accessOK == true)

        client.updateLanguage("vi")
        try await waitAsync { manager.stateLock.withLock { manager.rawCurrentLanguage == "vi" } }

        let batchOK = await withCheckedContinuation { cont in
            client.processPendingApps(approvedPIDs: [], rejectedPIDs: []) { cont.resume(returning: $0) }
        }
        #expect(batchOK == true)
    }

    @Test("ESXPCClient+Requests short-circuits false when extension is not installed or retries exhaust")
    func xpcRequestsFailFastAndExhaustRetries() async {
        let listener = NSXPCListener.anonymous()
        let deadEndpoint = listener.endpoint
        listener.resume()
        listener.invalidate()

        let notInstalled = makeClient(endpoint: deadEndpoint, isInstalled: false)
        let configAck = await withCheckedContinuation { cont in
            notInstalled.allowConfigAccess(100) { cont.resume(returning: $0) }
        }
        let batchAck = await withCheckedContinuation { cont in
            notInstalled.processPendingApps(approvedPIDs: [100], rejectedPIDs: []) { cont.resume(returning: $0) }
        }
        notInstalled.updateLanguage("en")
        #expect(configAck == false && batchAck == false)

        let retryClient = makeClient(endpoint: deadEndpoint, isInstalled: true)
        let exhaustedAccess = await withCheckedContinuation { cont in
            retryClient.allowConfigAccess(100, retry: 11) { cont.resume(returning: $0) }
        }
        let exhaustedBatch = await withCheckedContinuation { cont in
            retryClient.processPendingApps(approvedPIDs: [100], rejectedPIDs: [], retry: 6) {
                cont.resume(returning: $0)
            }
        }
        #expect(exhaustedAccess == false && exhaustedBatch == false)
    }

    private func makeClient(
        endpoint: NSXPCListenerEndpoint, isInstalled: Bool, onConnected: @escaping @Sendable () -> Void = {}
    ) -> ESXPCClient {
        ESXPCClient(configuration: ESXPCClientConfiguration(
            maxRetries: 2,
            connectionFactory: {
                let conn = NSXPCConnection(listenerEndpoint: endpoint)
                conn.remoteObjectInterface = NSXPCInterface(with: ESAppProtocol.self)
                conn.exportedInterface = NSXPCInterface(with: ESXPCProtocol.self)
                conn.exportedObject = MockESXPCNotificationSink()
                return conn
            },
            isExtensionInstalled: { isInstalled },
            onConnectionEstablished: onConnected,
            onMaxRetriesReached: {},
            reconnectDelay: { _, _ in 0.01 }
        ), connectOnInit: false)
    }
}

// MARK: - 3. LockES+SelfHealing Tests
@Suite("LockES Self-Healing & CDHash Refresh Tests", .serialized)
struct LockESSelfHealingTests {
    @Test("updateCDHashIfNeeded and applyHealedCDHashes normalize and persist only on real changes")
    @MainActor
    func updateAndApplyHealedCDHashes() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLockerHealTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let suiteName = "com.TranPhuong319.HealTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ConfigStore(baseDirectoryURL: tempDir, userDefaults: defaults, uid: 501)
        let lockES = LockES(configStore: store)
        let appPath = "/Applications/Demo.app"
        lockES.lockedApps[appPath] = LockedAppConfig(
            bundleID: "com.demo", path: appPath, name: "Demo", cdhash: "aaaa"
        )
        lockES.updateCDHashIfNeeded(for: appPath, cdhash: "   ")
        lockES.updateCDHashIfNeeded(for: appPath, cdhash: "AAAA")
        lockES.updateCDHashIfNeeded(for: "/Applications/Missing.app", cdhash: "bbbb")
        #expect(lockES.lockedApps[appPath]?.cdhash == "aaaa")
        lockES.updateCDHashIfNeeded(for: appPath, cdhash: "  BBBB1234 \n")
        #expect(lockES.lockedApps[appPath]?.cdhash == "bbbb1234")
        #expect(store.load().apps[appPath]?.cdhash == "bbbb1234")
        lockES.applyHealedCDHashes([appPath: "cccc5678"])
        #expect(lockES.lockedApps[appPath]?.cdhash == "cccc5678")
        #expect(store.load().apps[appPath]?.cdhash == "cccc5678")
    }

    @Test("detectStaleCDHash and handleInstalledAppsChanged heal outdated bundle hash on disk")
    @MainActor
    func detectStaleCDHashWithSignedBinary() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLockerSignHeal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let binURL = tempDir.appendingPathComponent("sample_bin")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: binURL)

        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", "--identifier", "com.test.sample", binURL.path]
        try codesign.run()
        codesign.waitUntilExit()
        #expect(codesign.terminationStatus == 0)

        let actualHash = try #require(cdHash(for: binURL.path)).lowercased()
        let lockES = LockES(configStore: ConfigStore(baseDirectoryURL: tempDir, uid: 501))
        let stale = LockedAppConfig(bundleID: "com.test.sample", path: binURL.path, name: "Sample", cdhash: "0000")
        let fresh = LockedAppConfig(bundleID: "com.test.sample", path: binURL.path, name: "Sample", cdhash: actualHash)
        let missing = tempDir.appendingPathComponent("none").path

        #expect(lockES.detectStaleCDHash(for: binURL.path, config: stale) == actualHash)
        #expect(lockES.detectStaleCDHash(for: binURL.path, config: fresh) == nil)
        #expect(lockES.detectStaleCDHash(for: missing, config: stale) == nil)

        lockES.lockedApps[binURL.path] = stale
        lockES.handleInstalledAppsChanged([
            InstalledApp(name: "Sample", bundleID: "com.test.sample", path: binURL.path)
        ])
        #expect(lockES.allApps.count == 1)
    }
}

// MARK: - 4. ActivityStore & LogStore State Machine Tests

@Suite("ActivityStore & LogStore Fetching, Filtering & Clear Tests", .serialized)
struct ActivityAndLogStoreStateTests {
    @Test("ActivityStore fetches, clears stale logs, enforces 2000 limit, and filters by search")
    @MainActor
    func activityStoreLifecycleAndFiltering() async throws {
        let now = Date()
        let batchBox = OSAllocatedUnfairLock(initialState: [
            AppLogEntry(
                date: now.addingTimeInterval(-10), subsystem: "com.TranPhuong319.AppLocker",
                category: "Security", level: .notice,
                message: "[SecurityEvent:Approved] App: Safari (PID 101) | Path: /Applications/Safari.app"
            )
        ])
        let store = ActivityStore(timeRange: .all) { since, strictlyAfter in
            batchBox.withLock { $0 }.filter { strictlyAfter ? $0.date > since : $0.date >= since }
        }
        store.reload()
        try await waitMain { !store.isLoading }
        #expect(store.items.count == 1 && store.items.first?.targetAppName == "Safari")
        store.clearLogs()
        #expect(store.items.isEmpty)
        await store.fetchLatest()
        #expect(store.items.isEmpty)

        let futureBatch = (1...2005).map { idx in
            AppLogEntry(
                date: Date().addingTimeInterval(Double(idx)),
                subsystem: "com.TranPhuong319.AppLocker", category: "Security", level: .notice,
                message: "[SecurityEvent:Approved] App: App\(idx) (PID \(idx)) | Path: /Applications/App\(idx).app"
            )
        }
        batchBox.withLock { $0 = futureBatch }
        await store.fetchLatest()
        #expect(store.rawItems.count == 2_000)

        store.searchText = "App2005"
        try await waitMain { store.items.count == 1 }
        #expect(store.items.first?.targetAppName == "App2005")
        store.stopPolling()
    }

    @Test("LogStore fetches, clears, applies multi-dimensional filter, and caps 2000 entries")
    @MainActor
    func logStoreLifecycleAndRealApplyFilters() async throws {
        let now = Date()
        let entriesBox = OSAllocatedUnfairLock(initialState: [
            AppLogEntry(
                date: now.addingTimeInterval(-10), subsystem: "com.TranPhuong319.AppLocker",
                category: "Policy", level: .error, message: "Policy write denied"
            ),
            AppLogEntry(
                date: now.addingTimeInterval(-5), subsystem: "com.TranPhuong319.AppLocker.ESExtension",
                category: "EndpointSecurity", level: .notice, message: "Blocked launch"
            )
        ])
        let store = LogStore(timeRange: .all) { since, strictlyAfter in
            entriesBox.withLock { $0 }.filter { strictlyAfter ? $0.date > since : $0.date >= since }
        }
        store.reload()
        try await waitMain { !store.isLoading }
        #expect(store.filteredEntries.count == 2)

        store.selectedSubsystem = .esExtension
        try await waitMain { store.filteredEntries.count == 1 }
        #expect(store.filteredEntries.first?.category == "EndpointSecurity")

        store.selectedSubsystem = .all
        store.selectedLevel = .error
        try await waitMain { store.filteredEntries.first?.message == "Policy write denied" }
        #expect(store.filteredEntries.count == 1)
        #expect(store.filteredEntries.first?.message == "Policy write denied")

        store.clearLogs()
        #expect(store.filteredEntries.isEmpty)

        let newest = (1...2005).map { idx in
            AppLogEntry(
                date: Date().addingTimeInterval(Double(idx)),
                subsystem: "com.TranPhuong319.AppLocker", category: "App", level: .info, message: "Line \(idx)"
            )
        }
        entriesBox.withLock { $0 = newest }
        store.selectedLevel = .all
        await store.fetchLatest()
        #expect(store.entries.count == 2_000)
        store.stopPolling()
    }

    @MainActor
    private func waitMain(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    }
}

private func waitAsync(condition: @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await condition()) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
}
