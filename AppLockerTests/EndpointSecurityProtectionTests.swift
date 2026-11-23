//
//  EndpointSecurityProtectionTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 4/11/26.
//

import Darwin
import EndpointSecurity
import Foundation
import os
import Testing

// Tests covering the 4 core Endpoint Security protection pillars (inspired by Google Santa architecture).
@Suite("Endpoint Security Core Protection Tests", .serialized)
struct EndpointSecurityProtectionTests {

    func makeAuditToken(pid: pid_t, pidversion: Int32 = 100, uid: uid_t = getuid()) -> audit_token_t {
        var token = audit_token_t()
        token.val.1 = uid
        token.val.2 = getgid()
        token.val.3 = uid
        token.val.4 = getgid()
        token.val.5 = UInt32(bitPattern: pid)
        token.val.7 = UInt32(bitPattern: pidversion)
        return token
    }

    // MARK: - Pillar 1: Dual-Block Race & Emergency Deadline Budget (Google Santa style)

    @Test("Emergency Deadline Budget clamps headroom to [1s, 5s] at 80% budget across all boundaries")
    func deadlineBudgetClampingAndCalculation() {
        let zeroBudget = ESClientObject.computeDeadlineBudget(nanosUntilDeadline: 0)
        #expect(zeroBudget.headroom == 1_000_000_000 && zeroBudget.processingBudget == 0)

        let subSecondBudget = ESClientObject.computeDeadlineBudget(nanosUntilDeadline: 500_000_000)
        #expect(subSecondBudget.headroom == 1_000_000_000 && subSecondBudget.processingBudget == 0)

        let shortBudget = ESClientObject.computeDeadlineBudget(nanosUntilDeadline: 2_000_000_000)
        #expect(shortBudget.headroom == 1_000_000_000 && shortBudget.processingBudget == 1_000_000_000)

        let lowerClamp = ESClientObject.computeDeadlineBudget(nanosUntilDeadline: 5_000_000_000)
        #expect(lowerClamp.headroom == 1_000_000_000 && lowerClamp.processingBudget == 4_000_000_000)

        let medBudget = ESClientObject.computeDeadlineBudget(nanosUntilDeadline: 10_000_000_000)
        #expect(medBudget.headroom == 2_000_000_000 && medBudget.processingBudget == 8_000_000_000)

        let upperClamp = ESClientObject.computeDeadlineBudget(nanosUntilDeadline: 25_000_000_000)
        #expect(upperClamp.headroom == 5_000_000_000 && upperClamp.processingBudget == 20_000_000_000)

        let longBudget = ESClientObject.computeDeadlineBudget(nanosUntilDeadline: 60_000_000_000)
        #expect(longBudget.headroom == 5_000_000_000 && longBudget.processingBudget == 55_000_000_000)
        #expect(ESManager.machTimeToNanos(0) == 0 && ESManager.machTimeToNanos(1_000_000) > 0)
    }

    @Test("ESSafetyValve Dual-Block Race ensures exactly 1 winner across 200 concurrent threads")
    func safetyValveConcurrencyRaceGuaranteesSingleWinner() async {
        let (valve, responder) = EndpointSecurityTestSupport.makeTestValve(
            eventType: ES_EVENT_TYPE_AUTH_UNLINK
        )

        let winCount = await withTaskGroup(of: Bool.self) { group in
            for idx in 0..<200 {
                group.addTask {
                    valve.respond((idx % 2 == 0) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY, cache: false)
                }
            }
            var wins = 0
            for await won in group where won { wins += 1 }
            return wins
        }

        #expect(winCount == 1)
        #expect(responder.callCount == 1)
    }

    @Test("ESSafetyValve branches AUTH_OPEN to flagsResult and other AUTH events to authResult")
    func safetyValveBranchesAuthOpenFlagsVersusAuthResult() {
        let (openAllowValve, openAllowRec) = EndpointSecurityTestSupport.makeTestValve(
            eventType: ES_EVENT_TYPE_AUTH_OPEN
        )
        #expect(openAllowValve.respond(ES_AUTH_RESULT_ALLOW, cache: true) == true)
        #expect(openAllowRec.lastMethod == .flagsResult(0xFFFFFFFF))
        #expect(openAllowRec.lastCache == true)

        let (openDenyValve, openDenyRec) = EndpointSecurityTestSupport.makeTestValve(
            eventType: ES_EVENT_TYPE_AUTH_OPEN
        )
        #expect(openDenyValve.respond(ES_AUTH_RESULT_DENY, cache: false) == true)
        #expect(openDenyRec.lastMethod == .flagsResult(0))
        #expect(openDenyRec.lastCache == false)

        let (renameValve, renameRec) = EndpointSecurityTestSupport.makeTestValve(
            eventType: ES_EVENT_TYPE_AUTH_RENAME
        )
        #expect(renameValve.respond(ES_AUTH_RESULT_DENY, cache: false) == true)
        #expect(renameRec.lastMethod == .authResult(ES_AUTH_RESULT_DENY))
    }

    @Test("ESSafetyValve suppresses duplicate responses on same message preventing kernel extension termination")
    func safetyValveSuppressesDuplicateResponsesPreventingKernelKill() {
        let responder = AuthResponseRecorder()
        var valve: ESSafetyValve? = ESSafetyValve(
            eventType: ES_EVENT_TYPE_AUTH_EXEC,
            actionType: ES_ACTION_TYPE_AUTH,
            responder: { method, cache in responder.recordMethod(method, cache: cache) }
        )

        // 1. First response on message succeeds
        let firstResult = valve?.respond(ES_AUTH_RESULT_ALLOW, cache: true)
        #expect(firstResult == true)
        #expect(responder.callCount == 1)
        #expect(responder.lastResult == ES_AUTH_RESULT_ALLOW)
        #expect(responder.lastCache == true)

        // 2. Intentional duplicate response on identical message must be filtered out
        let duplicateResult = valve?.respond(ES_AUTH_RESULT_ALLOW, cache: true)
        #expect(duplicateResult == false)
        #expect(responder.callCount == 1)

        // 3. Conflicting duplicate response (e.g. DENY after ALLOW) must also be filtered out
        let conflictingResult = valve?.respond(ES_AUTH_RESULT_DENY, cache: false)
        #expect(conflictingResult == false)
        #expect(responder.callCount == 1)
        #expect(responder.lastResult == ES_AUTH_RESULT_ALLOW)

        // 4. Deinit of already-responded valve must not trigger fallback response
        valve = nil
        #expect(responder.callCount == 1)
    }

    // MARK: - Pillar 2: Inverted Path Muting & 7-Event File Tamper Resistance (Google Santa style)

    @Test("ESAuthorizer and ESTamper subscribe to expected events and protect allowlist prefixes")
    func tamperAllowlistAndSubscribedEventsConfiguration() {
        #expect(ESAuthorizer.subscribedEvents.count == 3)
        #expect(ESAuthorizer.subscribedEvents.contains(ES_EVENT_TYPE_NOTIFY_EXEC))
        #expect(ESAuthorizer.subscribedEvents.contains(ES_EVENT_TYPE_AUTH_SIGNAL))
        #expect(ESAuthorizer.subscribedEvents.contains(ES_EVENT_TYPE_NOTIFY_EXIT))

        #expect(ESTamper.subscribedEvents.count == 7)
        #expect(ESTamper.subscribedEvents.contains(ES_EVENT_TYPE_AUTH_OPEN))
        #expect(ESTamper.subscribedEvents.contains(ES_EVENT_TYPE_AUTH_UNLINK))
        #expect(ESTamper.subscribedEvents.contains(ES_EVENT_TYPE_AUTH_RENAME))
        #expect(ESTamper.subscribedEvents.contains(ES_EVENT_TYPE_AUTH_TRUNCATE))
        #expect(ESTamper.subscribedEvents.contains(ES_EVENT_TYPE_AUTH_EXCHANGEDATA))
        #expect(ESTamper.subscribedEvents.contains(ES_EVENT_TYPE_AUTH_CLONE))
        #expect(ESTamper.subscribedEvents.contains(ES_EVENT_TYPE_AUTH_LINK))
        let allowlistPaths = ESTamper.protectedAllowlistPaths.map(\.path)
        #expect(allowlistPaths.contains("/Users/Shared/AppLocker"))
        #expect(allowlistPaths.contains("/Applications/AppLocker.app"))
        #expect(allowlistPaths.contains("/System/Volumes/Data/Users/Shared/AppLocker"))
        #expect(allowlistPaths.contains("/System/Volumes/Data/Applications/AppLocker.app"))
    }

    @Test("Fast-path read-only AUTH_OPEN allows with cache=true; write-intent from untrusted PID denies")
    func fileTamperReadOnlyFastPathAndWriteIntentDeny() {
        let manager = ESManager(isTesting: true)
        let untrustedPID: pid_t = 99_991
        let untrustedToken = makeAuditToken(pid: untrustedPID)
        let protectedPaths = [
            "/Users/Shared/AppLocker/config.plist",
            "/System/Volumes/Data/Users/Shared/AppLocker/501.plist",
            "/Applications/AppLocker.app/Contents/MacOS/AppLocker",
            "/System/Volumes/Data/Applications/AppLocker.app/Contents/Info.plist"
        ]

        for path in protectedPaths {
            let (readValve, readResp) = EndpointSecurityTestSupport.makeTestValve(
                eventType: ES_EVENT_TYPE_AUTH_OPEN
            )
            let readCtx = FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_OPEN, processPID: untrustedPID,
                processAuditToken: untrustedToken, primaryPath: path, openFlags: 0x00000001
            )
            manager.evaluateFileAuth(context: readCtx, valve: readValve)
            #expect(readResp.lastResult == ES_AUTH_RESULT_ALLOW)
            #expect(readResp.lastCache == true)

            let (writeValve, writeResp) = EndpointSecurityTestSupport.makeTestValve(
                eventType: ES_EVENT_TYPE_AUTH_OPEN
            )
            let writeCtx = FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_OPEN, processPID: untrustedPID,
                processAuditToken: untrustedToken, primaryPath: path, openFlags: 0x00000002 | Int32(O_TRUNC)
            )
            manager.evaluateFileAuth(context: writeCtx, valve: writeValve)
            #expect(writeResp.lastResult == ES_AUTH_RESULT_DENY)
            #expect(writeResp.lastCache == false)
        }
    }

    private func makeSevenMutationContexts(pid: pid_t, token: audit_token_t) -> [FileAuthEventContext] {
        [
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_OPEN, processPID: pid, processAuditToken: token,
                primaryPath: "/Users/Shared/AppLocker/config.plist", openFlags: Int32(O_CREAT) | 0x00000002
            ),
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_UNLINK, processPID: pid, processAuditToken: token,
                primaryPath: "/System/Volumes/Data/Users/Shared/AppLocker/config.plist"
            ),
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_RENAME, processPID: pid, processAuditToken: token,
                primaryPath: "/Users/Shared/AppLocker/config.plist", isRenameToNewPath: true,
                renameNewDir: "/Users/tester/.Trash", renameNewFilename: "config.plist"
            ),
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_TRUNCATE, processPID: pid, processAuditToken: token,
                primaryPath: "/Applications/AppLocker.app/Contents/MacOS/AppLocker"
            ),
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_EXCHANGEDATA, processPID: pid, processAuditToken: token,
                primaryPath: "/tmp/fake_binary",
                secondaryPath: "/System/Volumes/Data/Applications/AppLocker.app/Contents/MacOS/AppLocker"
            ),
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_CLONE, processPID: pid, processAuditToken: token,
                primaryPath: "/Users/Shared/AppLocker", secondaryPath: "/Applications/AppLocker.app"
            ),
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_LINK, processPID: pid, processAuditToken: token,
                primaryPath: "/Users/Shared/AppLocker",
                secondaryPath: "/Applications/AppLocker.app/Contents/MacOS/AppLocker"
            )
        ]
    }

    @Test("All 7 file mutation events deny untrusted processes and allow authenticated PIDs")
    func sevenFileMutationEventsTamperMatrix() {
        let manager = ESManager(isTesting: true)
        let untrustedPID: pid_t = 88_888
        let untrustedToken = makeAuditToken(pid: untrustedPID)
        let trustedPID: pid_t = getpid()
        let trustedToken = makeAuditToken(pid: trustedPID)

        for var ctx in makeSevenMutationContexts(pid: untrustedPID, token: untrustedToken) {
            let (denyValve, denyResponder) = EndpointSecurityTestSupport.makeTestValve(eventType: ctx.eventType)
            manager.evaluateFileAuth(context: ctx, valve: denyValve)
            #expect(denyResponder.lastResult == ES_AUTH_RESULT_DENY)
            #expect(denyResponder.lastCache == false)
            if ctx.eventType == ES_EVENT_TYPE_AUTH_RENAME {
                #expect(manager.isTrashDestination(ctx) == true)
            }

            ctx.processPID = trustedPID
            ctx.processAuditToken = trustedToken
            let (allowValve, allowResponder) = EndpointSecurityTestSupport.makeTestValve(eventType: ctx.eventType)
            manager.evaluateFileAuth(context: ctx, valve: allowValve)
            #expect(allowResponder.lastResult == ES_AUTH_RESULT_ALLOW)
            #expect(allowResponder.lastCache == false)
        }
    }

    @Test("Finder metadata allowlist (.DS_Store, .localized, .com.apple.*) is allowed with cache=true")
    func finderMetadataAllowlistAllowedWithCache() {
        let manager = ESManager(isTesting: true)
        let untrustedPID: pid_t = 77_777
        let allowedMetadataFiles = [
            "/Users/Shared/AppLocker/.DS_Store",
            "/Users/Shared/AppLocker/.localized",
            "/Users/Shared/AppLocker/.com.apple.timemachine.donotpresent"
        ]

        for file in allowedMetadataFiles {
            let (openValve, openResp) = EndpointSecurityTestSupport.makeTestValve(
                eventType: ES_EVENT_TYPE_AUTH_OPEN
            )
            let openCtx = FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_OPEN, processPID: untrustedPID,
                primaryPath: file, openFlags: 0x00000002 | Int32(O_CREAT)
            )
            manager.evaluateFileAuth(context: openCtx, valve: openValve)
            #expect(openResp.lastResult == ES_AUTH_RESULT_ALLOW)
            #expect(openResp.lastCache == true)

            let (unlinkValve, unlinkResp) = EndpointSecurityTestSupport.makeTestValve(
                eventType: ES_EVENT_TYPE_AUTH_UNLINK
            )
            let unlinkCtx = FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_UNLINK, processPID: untrustedPID, primaryPath: file
            )
            manager.evaluateFileAuth(context: unlinkCtx, valve: unlinkValve)
            #expect(unlinkResp.lastResult == ES_AUTH_RESULT_ALLOW)
            #expect(unlinkResp.lastCache == true)
        }
    }
}

extension EndpointSecurityProtectionTests {
    @Test("ESSafetyValve deinit triggers ALLOW fallback for unresponded AUTH events and stays silent for NOTIFY")
    func safetyValveDeinitFallbackAndNotifySilence() {
        func assertDeinit(_ eventType: es_event_type_t, _ actionType: es_action_type_t, _ expected: ESResponseMethod?) {
            let rec = AuthResponseRecorder()
            do {
                let valve = ESSafetyValve(
                    eventType: eventType, actionType: actionType,
                    responder: { rec.recordMethod($0, cache: $1) }
                )
                _ = valve
            }
            #expect(rec.callCount == (expected == nil ? 0 : 1))
            #expect(rec.lastMethod == expected)
            #expect(rec.lastCache == (expected == nil ? nil : false))
        }
        assertDeinit(ES_EVENT_TYPE_AUTH_UNLINK, ES_ACTION_TYPE_AUTH, .authResult(ES_AUTH_RESULT_ALLOW))
        assertDeinit(ES_EVENT_TYPE_AUTH_OPEN, ES_ACTION_TYPE_AUTH, .flagsResult(0xFFFFFFFF))
        assertDeinit(ES_EVENT_TYPE_NOTIFY_EXEC, ES_ACTION_TYPE_NOTIFY, nil)
    }

    @Test("Extreme Dual-Block Race Storm: 500 valves racing emergency DENY vs stalled & burst workers")
    func safetyValveExtremeDualBlockRaceStorm() async {
        let manager = ESManager(isTesting: true)
        let events: [es_event_type_t] = [
            ES_EVENT_TYPE_AUTH_OPEN, ES_EVENT_TYPE_AUTH_UNLINK,
            ES_EVENT_TYPE_AUTH_SIGNAL, ES_EVENT_TYPE_AUTH_RENAME
        ]

        await withTaskGroup(of: Void.self) { group in
            for idx in 0..<500 {
                let eventType = events[idx % events.count]
                group.addTask {
                    if idx.isMultiple(of: 2) {
                        await Self.runStalledWorkerDeadlineRace(manager: manager, eventType: eventType)
                    } else {
                        await Self.runBurstContentionRace(manager: manager, eventType: eventType)
                    }
                }
            }
        }
    }

    private static func runStalledWorkerDeadlineRace(manager: ESManager, eventType: es_event_type_t) async {
        let (valve, rec) = EndpointSecurityTestSupport.makeTestValve(eventType: eventType)
        let wins = OSAllocatedUnfairLock(initialState: (emergency: false, worker: false))
        let emergencyDone = DispatchSemaphore(value: 0)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let doneGroup = DispatchGroup()
            doneGroup.enter()
            manager.emergencyTimerQueue.asyncAfter(deadline: .now() + .milliseconds(2)) {
                let won = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                wins.withLock { $0.emergency = won }
                emergencyDone.signal()
                doneGroup.leave()
            }
            doneGroup.enter()
            manager.authorizationProcessingQueue.async {
                _ = emergencyDone.wait(timeout: .now() + .seconds(2))
                let won = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
                wins.withLock { $0.worker = won }
                doneGroup.leave()
            }
            doneGroup.notify(queue: manager.backgroundProcessingQueue) { continuation.resume() }
        }

        let outcome = wins.withLock { $0 }
        #expect(outcome.emergency == true && outcome.worker == false)
        #expect(rec.callCount == 1 && rec.lastResult == ES_AUTH_RESULT_DENY && rec.lastCache == false)
        if eventType == ES_EVENT_TYPE_AUTH_OPEN {
            #expect(rec.lastMethod == .flagsResult(0))
        }
    }

    private static func runBurstContentionRace(manager: ESManager, eventType: es_event_type_t) async {
        let recorder = AuthResponseRecorder()
        let winCount = OSAllocatedUnfairLock(initialState: 0)
        do {
            let valve = ESSafetyValve(
                eventType: eventType,
                responder: { recorder.recordMethod($0, cache: $1) }
            )
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let doneGroup = DispatchGroup()
                doneGroup.enter()
                manager.emergencyTimerQueue.async {
                    if valve.respond(ES_AUTH_RESULT_DENY, cache: false) { winCount.withLock { $0 += 1 } }
                    doneGroup.leave()
                }
                for racer in 0..<6 {
                    doneGroup.enter()
                    manager.authorizationProcessingQueue.async {
                        let res = racer.isMultiple(of: 2) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
                        if valve.respond(res, cache: racer.isMultiple(of: 2)) { winCount.withLock { $0 += 1 } }
                        doneGroup.leave()
                    }
                }
                doneGroup.notify(queue: manager.backgroundProcessingQueue) { continuation.resume() }
            }
        }
        #expect(winCount.withLock { $0 } == 1 && recorder.callCount == 1)
    }
}
