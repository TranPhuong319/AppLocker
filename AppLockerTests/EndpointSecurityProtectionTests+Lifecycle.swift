//
//  EndpointSecurityProtectionTests+Lifecycle.swift
//  AppLockerTests
//
//  Created by Doe Phương on 4/11/26.
//

import Darwin
import EndpointSecurity
import Foundation
import os
import Testing

// MARK: - Pillar 3 (Pre-SIGSTOP & Anti-PID-Recycling) & Pillar 4 (75s Watchdog & Disconnect Recovery)

extension EndpointSecurityProtectionTests {

    @Test("Pre-SIGSTOP pending registration blocks SIGCONT from unauthorized senders and recycled PIDs")
    func preSigstopPendingRegistrationAndAntiPidRecycling() throws {
        let (childProc, tempDir) = try spawnTemporarySleepProcess()
        let childPID = childProc.processIdentifier
        defer {
            kill(childPID, SIGKILL)
            kill(childPID, SIGCONT)
            childProc.waitUntilExit()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let execPath = tempDir.appendingPathComponent("sleep_test_bin").path
        let realToken = try #require(realAuditToken(for: childPID))
        let uid = audit_token_to_euid(realToken)
        let customCDHashData = Data(repeating: 0xAA, count: 20)
        let customCDHashHex = customCDHashData.hexEncodedString

        let manager = ESManager(isTesting: true)
        manager.stateLock.withLock { manager.lockedCDHashes[uid] = [customCDHashHex] }
        manager.evaluateNotifyExec(context: ExecEventContext(
            targetPID: childPID, targetAuditToken: realToken, uid: uid,
            path: execPath, cdhashData: customCDHashData, cdhashHex: customCDHashHex
        ))

        #expect(manager.isPendingVerification(pid: childPID) == true)

        let cases: [(pid_t, es_auth_result_t)] = [
            (1, ES_AUTH_RESULT_DENY), (4242, ES_AUTH_RESULT_DENY), (getpid(), ES_AUTH_RESULT_ALLOW)
        ]
        for (senderPID, expected) in cases {
            let sigResponder = MockAuthResponder()
            let sigCtx = SignalEventContext(
                targetPID: childPID, targetAuditToken: realToken, senderPID: senderPID, sig: SIGCONT
            )
            manager.evaluateAuthSignal(context: sigCtx, valve: sigResponder)
            #expect(sigResponder.callCount == 1)
            #expect(sigResponder.lastResult == expected)
            #expect(sigResponder.lastCache == false)
        }

        var recycledToken = realToken
        recycledToken.val.7 &+= 1
        let recycleResponder = MockAuthResponder()
        let recycleCtx = SignalEventContext(
            targetPID: childPID, targetAuditToken: recycledToken, senderPID: 4242, sig: SIGCONT
        )
        manager.evaluateAuthSignal(context: recycleCtx, valve: recycleResponder)
        #expect(recycleResponder.callCount == 1)
        #expect(recycleResponder.lastResult == ES_AUTH_RESULT_DENY)
        #expect(recycleResponder.lastCache == false)
    }

    @Test("Watchdog kills expired frozen process (SIGKILL+SIGCONT) and aborts if pidversion mismatches")
    func watchdogPurgeKillsMatchingProcessAndAbortsOnPidVersionMismatch() throws {
        let (childA, tempDirA) = try spawnTemporarySleepProcess()
        let pidA = childA.processIdentifier
        defer {
            kill(pidA, SIGKILL)
            kill(pidA, SIGCONT)
            try? FileManager.default.removeItem(at: tempDirA)
        }

        let tokenA = try #require(realAuditToken(for: pidA))
        kill(pidA, SIGSTOP)

        let manager = ESManager(isTesting: true)
        let expiredInstant = ContinuousClock.now - .seconds(120)
        let notifA = ESManager.BlockedNotification(
            name: "sleep_test_bin", path: tempDirA.appendingPathComponent("sleep_test_bin").path,
            cdhash: "deadbeef", parentPid: getpid(), uid: getuid(),
            signingID: "com.test.sleep", targetPid: pidA
        )
        manager.pendingPIDLock.withLock {
            manager.pendingVerificationProcesses[pidA] = ESManager.PendingProcessRecord(
                token: tokenA, notification: notifA, registeredAt: expiredInstant
            )
        }
        manager.purgeExpiredPendingProcesses(timeoutSeconds: 75.0)
        childA.waitUntilExit()
        #expect(childA.isRunning == false)

        let (childB, tempDirB) = try spawnTemporarySleepProcess()
        let pidB = childB.processIdentifier
        defer {
            kill(pidB, SIGKILL)
            kill(pidB, SIGCONT)
            childB.waitUntilExit()
            try? FileManager.default.removeItem(at: tempDirB)
        }

        var mutatedTokenB = try #require(realAuditToken(for: pidB))
        mutatedTokenB.val.7 &+= 99
        let staleTokenB = mutatedTokenB
        let notifB = ESManager.BlockedNotification(
            name: "sleep_reused", path: tempDirB.appendingPathComponent("sleep_test_bin").path,
            cdhash: "deadbeef", parentPid: getpid(), uid: getuid(),
            signingID: "com.test.sleep", targetPid: pidB
        )
        manager.pendingPIDLock.withLock {
            manager.pendingVerificationProcesses[pidB] = ESManager.PendingProcessRecord(
                token: staleTokenB, notification: notifB, registeredAt: expiredInstant
            )
        }
        manager.purgeExpiredPendingProcesses(timeoutSeconds: 75.0)
        #expect(kill(pidB, 0) == 0)
        #expect(childB.isRunning == true)
    }

    @Test("Main App XPC disconnect keeps queue Fail-Closed, refreshes timer, and re-notifies on reconnect")
    func mainAppDisconnectPreservesFailClosedQueueAndRenotifies() throws {
        let manager = ESManager(isTesting: true)
        let fakePID: pid_t = 54_321
        let oldInstant = ContinuousClock.now - .seconds(60)
        let uid = getuid()
        let notif = ESManager.BlockedNotification(
            name: "Calculator", path: "/System/Applications/Calculator.app/Contents/MacOS/Calculator",
            cdhash: "abcd1234", parentPid: getpid(), uid: uid,
            signingID: "com.apple.calculator", targetPid: fakePID
        )

        manager.pendingPIDLock.withLock {
            manager.pendingVerificationProcesses[fakePID] = ESManager.PendingProcessRecord(
                token: makeAuditToken(pid: fakePID, uid: uid),
                notification: notif,
                registeredAt: oldInstant
            )
        }

        manager.handleMainAppDisconnect()
        let verifiedRecord = try #require(manager.pendingPIDLock.withLock {
            manager.pendingVerificationProcesses[fakePID]
        })
        #expect(verifiedRecord.registeredAt > oldInstant)
        #expect(manager.lastKickstartedUID == uid)

        let sink = MockESXPCNotificationSink()
        let anonListener = NSXPCListener.anonymous()
        let delegate = MockXPCNotificationDelegate(sink: sink)
        anonListener.delegate = delegate
        anonListener.resume()

        let clientConn = NSXPCConnection(listenerEndpoint: anonListener.endpoint)
        clientConn.remoteObjectInterface = NSXPCInterface(with: ESXPCProtocol.self)
        clientConn.resume()
        defer {
            clientConn.invalidate()
            anonListener.invalidate()
        }

        manager.reNotifyPendingVerificationProcesses(to: clientConn, uid: uid)

        let deadline = Date().addingTimeInterval(2.0)
        while sink.blockedExecEvents.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        #expect(sink.blockedExecEvents.first?.pid == fakePID)
        #expect(sink.blockedExecEvents.first?.name == "Calculator")
    }

    // MARK: - Signal Anti-Tamper & Self-Defense Tests

    @Test("evaluateAuthSignal denies unauthorized SIGKILL and SIGSTOP targeting authenticated AppLocker PID")
    func evaluateAuthSignalDeniesHostileSignalsTargetingAppLocker() {
        let manager = ESManager(isTesting: true)
        let mainAppPID: pid_t = 3096
        let token = makeAuditToken(pid: mainAppPID, pidversion: 100)

        manager.processIDLock.withLock {
            manager.authenticatedMainAppPID = mainAppPID
            manager.authenticatedMainAppPIDVersion = 100
        }

        for hostileSig in [SIGKILL, SIGSTOP, SIGTERM, SIGQUIT, SIGHUP, SIGINT] {
            let responder = MockAuthResponder()
            let ctx = SignalEventContext(
                targetPID: mainAppPID,
                targetAuditToken: token,
                senderPID: 9999,
                senderExecutablePath: "/bin/kill",
                sig: hostileSig
            )
            manager.evaluateAuthSignal(context: ctx, valve: responder)
            #expect(responder.callCount == 1)
            #expect(responder.lastResult == ES_AUTH_RESULT_DENY)
            #expect(responder.lastCache == false)
        }
    }

    @Test("evaluateAuthSignal denies Activity Monitor force quit targeting AppLocker PID")
    func evaluateAuthSignalDeniesActivityMonitorTargetingAppLocker() {
        let manager = ESManager(isTesting: true)
        let mainAppPID: pid_t = 3096
        let token = makeAuditToken(pid: mainAppPID, pidversion: 100)
        manager.processIDLock.withLock {
            manager.authenticatedMainAppPID = mainAppPID
            manager.authenticatedMainAppPIDVersion = 100
        }

        let responder = MockAuthResponder()
        let actMonPath = "/System/Applications/Utilities/Activity Monitor.app/Contents/MacOS/Activity Monitor"
        let ctx = SignalEventContext(
            targetPID: mainAppPID, targetAuditToken: token,
            senderPID: 5555, senderExecutablePath: actMonPath, sig: SIGKILL
        )
        manager.evaluateAuthSignal(context: ctx, valve: responder)
        #expect(responder.callCount == 1 && responder.lastResult == ES_AUTH_RESULT_DENY)
        #expect(responder.lastCache == false)
    }

    @Test("evaluateAuthSignal denies unauthorized SIGKILL targeting ESExtension getpid()")
    func evaluateAuthSignalDeniesHostileSignalTargetingExtension() {
        let manager = ESManager(isTesting: true)
        let extPID = getpid()
        let token = makeAuditToken(pid: extPID, pidversion: 100)
        let responder = MockAuthResponder()
        let ctx = SignalEventContext(
            targetPID: extPID, targetAuditToken: token,
            senderPID: 8888, senderExecutablePath: "/bin/kill", sig: SIGKILL
        )
        manager.evaluateAuthSignal(context: ctx, valve: responder)
        #expect(responder.callCount == 1 && responder.lastResult == ES_AUTH_RESULT_DENY)
        #expect(responder.lastCache == false)
    }

    @Test("evaluateAuthSignal allows autonomous launchd (PID 1) during OS shutdown")
    func evaluateAuthSignalAllowsAutonomousLaunchdDuringShutdown() {
        let manager = ESManager(isTesting: true)
        let mainAppPID: pid_t = 3096
        let token = makeAuditToken(pid: mainAppPID, pidversion: 100)
        manager.processIDLock.withLock {
            manager.authenticatedMainAppPID = mainAppPID
            manager.authenticatedMainAppPIDVersion = 100
        }

        let responder = MockAuthResponder()
        let ctx = SignalEventContext(
            targetPID: mainAppPID, targetAuditToken: token,
            senderPID: 1, senderExecutablePath: "/sbin/launchd", sig: SIGTERM
        )
        manager.evaluateAuthSignal(context: ctx, valve: responder)
        #expect(responder.callCount == 1 && responder.lastResult == ES_AUTH_RESULT_ALLOW)
    }

    @Test("evaluateAuthSignal allows self-signaling, SIGCHLD, sig 0, and authorized shutdown")
    func evaluateAuthSignalAllowsSelfSignalingAndAuthorizedShutdown() {
        let manager = ESManager(isTesting: true)
        let mainAppPID: pid_t = 3096
        let token = makeAuditToken(pid: mainAppPID, pidversion: 100)
        manager.processIDLock.withLock {
            manager.authenticatedMainAppPID = mainAppPID
            manager.authenticatedMainAppPIDVersion = 100
        }

        for (sender, sig) in [(mainAppPID, SIGTERM), (9999, 0), (9999, SIGCHLD)] {
            let resp = MockAuthResponder()
            let ctx = SignalEventContext(
                targetPID: mainAppPID, targetAuditToken: token, senderPID: sender, sig: sig
            )
            manager.evaluateAuthSignal(context: ctx, valve: resp)
            #expect(resp.callCount == 1 && resp.lastResult == ES_AUTH_RESULT_ALLOW)
        }

        manager.stateLock.withLock { manager.isShutdownAuthorized = true }
        let shutdownResponder = MockAuthResponder()
        let shutdownCtx = SignalEventContext(
            targetPID: mainAppPID, targetAuditToken: token, senderPID: 9999, sig: SIGKILL
        )
        manager.evaluateAuthSignal(context: shutdownCtx, valve: shutdownResponder)
        #expect(shutdownResponder.callCount == 1 && shutdownResponder.lastResult == ES_AUTH_RESULT_ALLOW)
    }

    @Test("ESSafetyValve filters duplicate AUTH_SIGNAL evaluations and enforces 80/20 deadline race")
    func authSignalSafetyValveDuplicateFilteringAndDeadlineTiming() {
        let manager = ESManager(isTesting: true)
        let mainAppPID: pid_t = 3096
        let token = makeAuditToken(pid: mainAppPID, pidversion: 100)
        manager.processIDLock.withLock {
            manager.authenticatedMainAppPID = mainAppPID
            manager.authenticatedMainAppPIDVersion = 100
            manager.lastKnownMainAppPID = mainAppPID
        }

        let recycledMainToken = makeAuditToken(pid: mainAppPID, pidversion: 101)
        #expect(manager.isMainAppTarget(targetPid: mainAppPID, targetToken: recycledMainToken) == false)

        let budget = ESClientObject.computeDeadlineBudget(nanosUntilDeadline: 15_000_000_000)
        #expect(budget.processingBudget == 12_000_000_000 && budget.headroom == 3_000_000_000)

        let recorder = MockAuthResponder()
        let valve = ESSafetyValve(
            eventType: ES_EVENT_TYPE_AUTH_SIGNAL,
            responder: { method, cache in recorder.recordMethod(method, cache: cache) }
        )
        let ctx = SignalEventContext(
            targetPID: mainAppPID, targetAuditToken: token,
            senderPID: 9999, senderExecutablePath: "/usr/bin/python3", sig: SIGKILL
        )
        manager.evaluateAuthSignal(context: ctx, valve: valve)
        manager.evaluateAuthSignal(context: ctx, valve: valve)
        #expect(valve.respond(ES_AUTH_RESULT_ALLOW, cache: false) == false)
        #expect(recorder.callCount == 1 && recorder.lastResult == ES_AUTH_RESULT_DENY)
    }

    @Test("Extreme Matrix: non-TTY platform binaries, exotic deadly signals, XPC disconnect PID reuse & burst storm")
    func extremeAdversarialSignalMatrixAndConcurrencyStorm() async {
        let manager = ESManager(isTesting: true)
        let (mainPID, pendingPID): (pid_t, pid_t) = (3096, 7777)
        let mainToken = makeAuditToken(pid: mainPID, pidversion: Int32.max)
        let pendingToken = makeAuditToken(pid: pendingPID, pidversion: 42)
        manager.processIDLock.withLock {
            manager.authenticatedMainAppPID = mainPID
            manager.authenticatedMainAppPIDVersion = Int32.max
            manager.lastKnownMainAppPID = mainPID
        }
        let notif = ESManager.BlockedNotification(
            name: "Safari", path: "/Applications/Safari.app", cdhash: "aa",
            parentPid: 1, uid: getuid(), signingID: "com.apple.Safari", targetPid: pendingPID
        )
        let pendingRec = ESManager.PendingProcessRecord(token: pendingToken, notification: notif, registeredAt: .now)
        manager.pendingPIDLock.withLock { manager.pendingVerificationProcesses[pendingPID] = pendingRec }

        let vectors = ["/usr/bin/python3", "/usr/bin/osascript", "/usr/bin/lldb", "/Applications/Warp.app"]
        let signals = [SIGABRT, SIGSEGV, SIGBUS, SIGALRM, SIGUSR1, SIGUSR2, SIGTTIN, SIGTTOU, SIGTRAP, SIGSYS]
        for vector in vectors {
            for sig in signals {
                let resp = MockAuthResponder()
                let ctx = SignalEventContext(
                    targetPID: mainPID, targetAuditToken: mainToken,
                    senderPID: 6000, senderExecutablePath: vector, sig: sig
                )
                manager.evaluateAuthSignal(context: ctx, valve: resp)
                #expect(resp.callCount == 1 && resp.lastResult == ES_AUTH_RESULT_DENY)
            }
        }

        manager.processIDLock.withLock { manager.authenticatedMainAppPID = nil }
        let recycledResp = MockAuthResponder()
        let recycledCtx = SignalEventContext(
            targetPID: mainPID, targetAuditToken: mainToken, senderPID: 6000, sig: SIGKILL
        )
        manager.evaluateAuthSignal(context: recycledCtx, valve: recycledResp)
        #expect(recycledResp.callCount == 1 && recycledResp.lastResult == ES_AUTH_RESULT_ALLOW)

        await withTaskGroup(of: Int.self) { group in
            for idx in 0..<300 {
                group.addTask {
                    let rec = MockAuthResponder()
                    let valve = ESSafetyValve(eventType: ES_EVENT_TYPE_AUTH_SIGNAL) { rec.recordMethod($0, cache: $1) }
                    manager.evaluateAuthSignal(context: .init(
                        targetPID: pendingPID, targetAuditToken: pendingToken,
                        senderPID: (idx % 2 == 0) ? getpid() : 8888, sig: SIGCONT
                    ), valve: valve)
                    _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                    return rec.callCount
                }
            }
            for await count in group { #expect(count == 1) }
        }
    }
}
