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

    func realAuditToken(for pid: pid_t) -> audit_token_t? {
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

    func spawnTemporarySleepProcess() throws -> (Process, URL) {
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

    // MARK: - Pillar 1: Dual-Block Race & Emergency Deadline Budget (Google Santa style)

    @Test("Emergency Deadline Budget clamps headroom to [1s, 5s] at 80% budget")
    func deadlineBudgetClampingAndCalculation() {
        let shortBudget = ESClientObject.computeDeadlineBudget(nanosUntilDeadline: 2_000_000_000)
        #expect(shortBudget.headroom == 1_000_000_000)
        #expect(shortBudget.processingBudget == 1_000_000_000)

        let medBudget = ESClientObject.computeDeadlineBudget(nanosUntilDeadline: 10_000_000_000)
        #expect(medBudget.headroom == 2_000_000_000)
        #expect(medBudget.processingBudget == 8_000_000_000)

        let longBudget = ESClientObject.computeDeadlineBudget(nanosUntilDeadline: 60_000_000_000)
        #expect(longBudget.headroom == 5_000_000_000)
        #expect(longBudget.processingBudget == 55_000_000_000)
        #expect(ESManager.machTimeToNanos(1_000_000) > 0)
    }

    @Test("ESSafetyValve Dual-Block Race ensures exactly 1 winner across 200 concurrent threads")
    func safetyValveConcurrencyRaceGuaranteesSingleWinner() async {
        let responder = MockAuthResponder()
        let valve = ESSafetyValve(
            eventType: ES_EVENT_TYPE_AUTH_UNLINK,
            responder: { method, cache in responder.recordMethod(method, cache: cache) }
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
        let openAllowRec = MockAuthResponder()
        let openAllowValve = ESSafetyValve(
            eventType: ES_EVENT_TYPE_AUTH_OPEN, responder: { openAllowRec.recordMethod($0, cache: $1) }
        )
        #expect(openAllowValve.respond(ES_AUTH_RESULT_ALLOW, cache: true) == true)
        #expect(openAllowRec.lastMethod == .flagsResult(0xFFFFFFFF))
        #expect(openAllowRec.lastCache == true)

        let openDenyRec = MockAuthResponder()
        let openDenyValve = ESSafetyValve(
            eventType: ES_EVENT_TYPE_AUTH_OPEN, responder: { openDenyRec.recordMethod($0, cache: $1) }
        )
        #expect(openDenyValve.respond(ES_AUTH_RESULT_DENY, cache: false) == true)
        #expect(openDenyRec.lastMethod == .flagsResult(0))
        #expect(openDenyRec.lastCache == false)

        let renameRec = MockAuthResponder()
        let renameValve = ESSafetyValve(
            eventType: ES_EVENT_TYPE_AUTH_RENAME, responder: { renameRec.recordMethod($0, cache: $1) }
        )
        #expect(renameValve.respond(ES_AUTH_RESULT_DENY, cache: false) == true)
        #expect(renameRec.lastMethod == .authResult(ES_AUTH_RESULT_DENY))
    }

    // MARK: - Pillar 2: Inverted Path Muting & 7-Event File Tamper Resistance (Google Santa style)

    @Test("ESTamper subscribes to 7 file events and protects allowlist prefixes")
    func tamperAllowlistAndSubscribedEventsConfiguration() {
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
            let readResp = MockAuthResponder()
            let readCtx = FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_OPEN, processPID: untrustedPID,
                processAuditToken: untrustedToken, primaryPath: path, openFlags: 0x00000001
            )
            manager.evaluateFileAuth(context: readCtx, valve: readResp)
            #expect(readResp.lastResult == ES_AUTH_RESULT_ALLOW)
            #expect(readResp.lastCache == true)

            let writeResp = MockAuthResponder()
            let writeCtx = FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_OPEN, processPID: untrustedPID,
                processAuditToken: untrustedToken, primaryPath: path, openFlags: 0x00000002 | Int32(O_TRUNC)
            )
            manager.evaluateFileAuth(context: writeCtx, valve: writeResp)
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
            let denyResponder = MockAuthResponder()
            manager.evaluateFileAuth(context: ctx, valve: denyResponder)
            #expect(denyResponder.lastResult == ES_AUTH_RESULT_DENY)
            #expect(denyResponder.lastCache == false)
            if ctx.eventType == ES_EVENT_TYPE_AUTH_RENAME {
                #expect(manager.isTrashDestination(ctx) == true)
            }

            ctx.processPID = trustedPID
            ctx.processAuditToken = trustedToken
            let allowResponder = MockAuthResponder()
            manager.evaluateFileAuth(context: ctx, valve: allowResponder)
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
            let openResp = MockAuthResponder()
            let openCtx = FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_OPEN, processPID: untrustedPID,
                primaryPath: file, openFlags: 0x00000002 | Int32(O_CREAT)
            )
            manager.evaluateFileAuth(context: openCtx, valve: openResp)
            #expect(openResp.lastResult == ES_AUTH_RESULT_ALLOW)
            #expect(openResp.lastCache == true)

            let unlinkResp = MockAuthResponder()
            let unlinkCtx = FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_UNLINK, processPID: untrustedPID, primaryPath: file
            )
            manager.evaluateFileAuth(context: unlinkCtx, valve: unlinkResp)
            #expect(unlinkResp.lastResult == ES_AUTH_RESULT_ALLOW)
            #expect(unlinkResp.lastCache == true)
        }
    }
}
