//
//  LaunchHandoverAndSingleInstanceTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 17/11/26.
//

import Foundation
import Testing

@Suite("Launch Handover & Single-Instance Policy Tests")
struct LaunchHandoverAndSingleInstanceTests {

    @Test("Manual launch hands over to launchd immediately when kickstart succeeds")
    func manualHandoverSucceedsOnFirstKickstart() async {
        var kickstartCalls = 0
        var forceReRegisterCalls = 0

        let decision = await LaunchBootstrapPolicy.resolveHandover(
            isAgentActive: { true },
            installAgent: { Issue.record("installAgent should not be called when already active") },
            kickstart: {
                kickstartCalls += 1
                return true
            },
            forceReRegister: {
                forceReRegisterCalls += 1
                return true
            }
        )

        #expect(decision == .terminateManualAndHandover)
        #expect(kickstartCalls == 1)
        #expect(forceReRegisterCalls == 0)
    }

    @Test("Manual launch after bootout force re-registers once without second kickstart")
    func manualHandoverAfterBootoutSkipsSecondKickstart() async {
        var kickstartCalls = 0
        var forceReRegisterCalls = 0

        let decision = await LaunchBootstrapPolicy.resolveHandover(
            isAgentActive: { true },
            installAgent: {},
            kickstart: {
                kickstartCalls += 1
                return false
            },
            forceReRegister: {
                forceReRegisterCalls += 1
                return true
            }
        )

        #expect(decision == .terminateManualAndHandover)
        #expect(kickstartCalls == 1)
        #expect(forceReRegisterCalls == 1)
    }

    @Test("Manual launch continues directly when agent cannot be activated")
    func manualContinuesWhenAgentInstallFails() async {
        var installCalls = 0
        var kickstartCalls = 0

        let decision = await LaunchBootstrapPolicy.resolveHandover(
            isAgentActive: { false },
            installAgent: { installCalls += 1 },
            kickstart: {
                kickstartCalls += 1
                return true
            },
            forceReRegister: { true }
        )

        #expect(decision == .continueManual)
        #expect(installCalls == 1)
        #expect(kickstartCalls == 0)
    }

    @Test("Manual launch falls back to running directly when kickstart and re-register fail")
    func manualFallsBackWhenBothKickstartAndReRegisterFail() async {
        let decision = await LaunchBootstrapPolicy.resolveHandover(
            isAgentActive: { true },
            installAgent: {},
            kickstart: { false },
            forceReRegister: { false }
        )

        #expect(decision == .continueManual)
    }

    @Test("Spawning duplicate manual process activates existing instance and terminates new one")
    func duplicateManualProcessTerminatesSelf() {
        let decision = LaunchBootstrapPolicy.resolveSingleInstance(
            isLaunchedByLaunchd: false,
            currentPID: 9171,
            runningPIDs: [9166, 9171]
        )

        #expect(decision == .activateAndTerminateSelf(targetPID: 9166))
    }

    @Test("Launchd instance terminates lingering manual instance instead of terminating itself")
    func launchdInstanceTakesOverFromManualInstance() {
        let decision = LaunchBootstrapPolicy.resolveSingleInstance(
            isLaunchedByLaunchd: true,
            currentPID: 9171,
            runningPIDs: [9166, 9171]
        )

        #expect(decision == .terminateOtherManualInstances([9166]))
    }

    @Test("Relaunch ignores exiting parent PID via -waitForPID and proceeds")
    func relaunchIgnoresParentPID() {
        let decision = LaunchBootstrapPolicy.resolveSingleInstance(
            isLaunchedByLaunchd: false,
            currentPID: 2002,
            ignoringPID: 2001,
            runningPIDs: [2001, 2002]
        )

        #expect(decision == .proceed)
    }
}

@Suite("Main App Hang, Stall & Race Stress Verification Tests", .serialized)
@MainActor
struct MainAppHangAndStressVerificationTests {

    private func makeStressCoordinator() -> AuthCoordinator {
        let coordinator = AuthCoordinator()
        coordinator.dependencies.isBatchWindowVisible = { false }
        coordinator.dependencies.showBatchWindow = {}
        coordinator.dependencies.hideBatchWindow = {}
        coordinator.dependencies.sendBlockedNotification = { _ in }
        coordinator.dependencies.cancelAuth = {}
        coordinator.dependencies.refreshWatchdog = { _ in }
        coordinator.dependencies.processPendingApps = { _, _, _ in }
        coordinator.dependencies.sleep = { _ in await Task.yield() }
        return coordinator
    }

    @Test("Repro Bug #5a: Late single-auth completion after watchdog force-reject clobbers active session")
    func lateSingleAuthCompletionClobbersActiveSessionAndWatchdog() async {
        let coordinator = makeStressCoordinator()
        var capturedContinuations: [CheckedContinuation<Bool, Error>] = []
        coordinator.dependencies.authenticate = { _ in
            try await withCheckedThrowingContinuation { cont in
                capturedContinuations.append(cont)
            }
        }

        // 1. Start App A; mock sleep yields immediately so watchdog force-rejects App A
        coordinator.addPendingAuth(name: "AppA", path: "/Applications/AppA.app", cdhash: "a", pid: 8101)
        coordinator.processIncomingQueue()
        for _ in 0..<20 where coordinator.phase != .idle || capturedContinuations.isEmpty {
            await Task.yield()
        }
        #expect(capturedContinuations.count == 1)
        #expect(coordinator.phase == .idle)

        // 2. Now hold sleep for App B so App B stays actively authenticating
        coordinator.dependencies.sleep = { _ in try await Task.sleep(for: .seconds(60)) }
        coordinator.addPendingAuth(name: "AppB", path: "/Applications/AppB.app", cdhash: "b", pid: 8102)
        coordinator.processIncomingQueue()
        for _ in 0..<20 where capturedContinuations.count < 2 {
            await Task.yield()
        }
        #expect(coordinator.phase == .single(pid: 8102, upgradingToBatch: false))
        #expect(coordinator.singleAppWatchdogTask != nil)

        // 3. Stale LAContext for App A finally resumes late -> must NOT clobber App B!
        capturedContinuations[0].resume(returning: false)
        for _ in 0..<10 { await Task.yield() }

        #expect(coordinator.phase == .single(pid: 8102, upgradingToBatch: false))
        #expect(coordinator.singleAppWatchdogTask != nil)

        // Cleanup App B continuation
        capturedContinuations[1].resume(returning: false)
        for _ in 0..<10 { await Task.yield() }
        coordinator.handleCancel()
    }

    @Test("Batch authenticate watchdog cancels stalled Touch ID prompt and rejects PIDs")
    func batchAuthenticateWatchdogCancelsStalledBatchPrompt() async {
        let coordinator = makeStressCoordinator()
        var authCont: CheckedContinuation<Bool, Error>?
        var rejectedPIDs: [Int32] = []
        var rejectionReason = ""
        coordinator.dependencies.authenticate = { _ in
            try await withCheckedThrowingContinuation { authCont = $0 }
        }
        coordinator.dependencies.processPendingApps = { _, rejected, reason in
            rejectedPIDs = rejected
            rejectionReason = reason
        }

        coordinator.addPendingAuth(name: "App1", path: "/Applications/App1.app", cdhash: "h1", pid: 8201)
        coordinator.addPendingAuth(name: "App2", path: "/Applications/App2.app", cdhash: "h2", pid: 8202)
        coordinator.handleAuthenticate()
        #expect(coordinator.phase == .batch(restartingWithNewApps: false))
        #expect(coordinator.singleAppWatchdogTask != nil)

        // Wait for watchdog timer + 2s fallback (instant in mock sleep) to force-reject
        for _ in 0..<25 where coordinator.phase != .idle { await Task.yield() }

        #expect(coordinator.phase == .idle)
        #expect(Set(rejectedPIDs) == [8201, 8202])
        #expect(rejectionReason == AuthDecisionReason.timeout.rawValue)

        // Late resumption after watchdog force-reject must be ignored cleanly
        authCont?.resume(returning: false)
        for _ in 0..<10 { await Task.yield() }
        #expect(coordinator.phase == .idle)
    }

    @Test("Stress: AuthCoordinator handles 50 rapid blocked execs + 25 interleaved exits without stuck state")
    func authCoordinatorRapidBurstAndInterleavedExitStorm() async {
        let coordinator = makeStressCoordinator()
        var batchVisible = false
        var decidedPIDs = Set<Int32>()
        coordinator.dependencies.isBatchWindowVisible = { batchVisible }
        coordinator.dependencies.showBatchWindow = { batchVisible = true }
        coordinator.dependencies.hideBatchWindow = { batchVisible = false }
        coordinator.dependencies.authenticate = { _ in true }
        coordinator.dependencies.processPendingApps = { approved, rejected, _ in
            decidedPIDs.formUnion(approved)
            decidedPIDs.formUnion(rejected)
        }

        for idx in 0..<50 {
            let pid = Int32(9000 + idx)
            coordinator.addPendingAuth(
                name: "App\(idx)", path: "/Applications/App\(idx).app", cdhash: "h\(idx)", pid: pid
            )
        }
        coordinator.processIncomingQueue()
        #expect(batchVisible == true && coordinator.pendingApps.count == 50)

        for idx in stride(from: 0, to: 50, by: 2) {
            coordinator.removePendingProcess(pid: Int32(9000 + idx))
        }
        #expect(coordinator.pendingApps.count == 25)

        coordinator.handleAuthenticate()
        for _ in 0..<20 where coordinator.phase != .idle { await Task.yield() }

        #expect(coordinator.phase == .idle)
        #expect(coordinator.pendingApps.isEmpty && coordinator.activeBatchApps.isEmpty)
        #expect(decidedPIDs.count == 25)
    }

    @Test("Stress: LockES.toggleLockAsync and AppState.refreshAppLists MainActor blocking with 30 app bundles")
    func lockESToggleLockAndRefreshMainThreadStressMeasurement() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLockerMainStress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let suiteName = "com.TranPhuong319.MainStress.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        var appPaths: [String] = []
        for idx in 0..<30 {
            let appURL = tempDir.appendingPathComponent("StressApp\(idx).app", isDirectory: true)
            let macOSDir = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
            try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "CFBundleIdentifier": "com.stress.app\(idx)",
                "CFBundleExecutable": "StressApp\(idx)",
                "CFBundleName": "StressApp\(idx)"
            ]
            let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try plistData.write(to: appURL.appendingPathComponent("Contents/Info.plist"))
            let binURL = macOSDir.appendingPathComponent("StressApp\(idx)")
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: binURL)
            appPaths.append(appURL.path)
        }

        let store = ConfigStore(baseDirectoryURL: tempDir, userDefaults: defaults, uid: 501)
        let manager = LockES(configStore: store)
        let state = AppState(manager: manager, isMock: true, installedAppsProvider: { [] })

        let startTime = ContinuousClock.now
        await manager.toggleLockAsync(for: appPaths)
        let afterLock = ContinuousClock.now
        state.refreshAppLists()
        let afterRefresh = ContinuousClock.now

        let lockDur = afterLock - startTime
        let refreshDur = afterRefresh - afterLock
        let lockMs = lockDur.components.seconds * 1000 + lockDur.components.attoseconds / 1_000_000_000_000_000
        let refreshMs = refreshDur.components.seconds * 1000 + refreshDur.components.attoseconds / 1_000_000_000_000_000
        Logfile.app.notice(
            """
            [StressBenchmark:MainActor] 30 signed bundles -> \
            toggleLockAsync: \(lockMs, privacy: .public)ms, \
            refreshAppLists(cachedName+noPreload): \(refreshMs, privacy: .public)ms
            """
        )

        #expect(manager.lockedApps.count == 30)
        #expect(state.lockedAppObjects.count == 30)
    }

    @Test("AppIconProvider.loadIcon caches valid app icons asynchronously and handles missing paths")
    func appIconProviderLoadsAndCachesIconsAsynchronously() async {
        let provider = AppIconProvider.shared
        let calcPath = "/System/Applications/Calculator.app"
        provider.invalidateIcon(for: calcPath)
        #expect(provider.cachedIcon(for: calcPath, size: 32) == nil)

        let loaded = await provider.loadIcon(for: calcPath, size: 32)
        #expect(loaded.size == NSSize(width: 32, height: 32))
        #expect(provider.cachedIcon(for: calcPath, size: 32) != nil)

        let missingPath = "/tmp/NonExistent-\(UUID().uuidString).app"
        let missing = await provider.loadIcon(for: missingPath, size: 32)
        #expect(missing.isTemplate == true)
        #expect(provider.cachedIcon(for: missingPath, size: 32) == nil)
    }
}
