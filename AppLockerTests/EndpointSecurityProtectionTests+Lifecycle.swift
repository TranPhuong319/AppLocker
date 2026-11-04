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
        manager.evaluateNotifyExec(
            context: ExecEventContext(
                targetPID: childPID,
                targetAuditToken: realToken,
                uid: uid,
                path: execPath,
                cdhashData: customCDHashData,
                cdhashHex: customCDHashHex
            )
        )

        #expect(manager.isPendingVerification(pid: childPID) == true)

        for senderPID in [pid_t(1), pid_t(4242)] {
            let sigResponder = MockAuthResponder()
            let sigCtx = SignalEventContext(
                targetPID: childPID,
                targetAuditToken: realToken,
                senderPID: senderPID,
                sig: SIGCONT
            )
            manager.evaluateAuthSignal(context: sigCtx, valve: sigResponder)
            #expect(sigResponder.lastResult == ES_AUTH_RESULT_DENY)
            #expect(sigResponder.lastCache == false)
        }

        var recycledToken = realToken
        recycledToken.val.7 &+= 1
        let recycleResponder = MockAuthResponder()
        let recycleCtx = SignalEventContext(
            targetPID: childPID,
            targetAuditToken: recycledToken,
            senderPID: 4242,
            sig: SIGCONT
        )
        manager.evaluateAuthSignal(context: recycleCtx, valve: recycleResponder)
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
}
