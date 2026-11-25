//
//  EndpointSecurityTamperHardeningTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 25/11/26.
//

import Darwin
import EndpointSecurity
import Foundation
import os
import Testing

@Suite("EndpointSecurity Hardening, Config Monitoring & Migration Tests", .serialized)
struct EndpointSecurityTamperHardeningTests {
    private func makeAuditToken(pid: pid_t, pidversion: Int32, uid: uid_t = 501) -> audit_token_t {
        var token = audit_token_t()
        token.val.1 = uid
        token.val.2 = getgid()
        token.val.3 = uid
        token.val.4 = getgid()
        token.val.5 = UInt32(bitPattern: pid)
        token.val.7 = UInt32(bitPattern: pidversion)
        return token
    }

    @Test("ESTamper isAuthorized rejects PID-recycled process whose pidversion mismatches authenticatedMainAppPID")
    func isAuthorizedRejectsPidVersionMismatch() {
        let manager = ESManager(isTesting: true)
        let mainPID: pid_t = 44_445
        manager.processIDLock.withLock {
            manager.authenticatedMainAppPID = mainPID
            manager.authenticatedMainAppPIDVersion = 100
        }

        let targetPath = "/Users/Shared/AppLocker/501/config.plist"
        let staleToken = makeAuditToken(pid: mainPID, pidversion: 101, uid: 501)
        let (denyValve, denyResp) = EndpointSecurityTestSupport.makeTestValve(eventType: ES_EVENT_TYPE_AUTH_OPEN)
        manager.evaluateFileAuth(
            context: FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_OPEN,
                processPID: mainPID,
                processAuditToken: staleToken,
                primaryPath: targetPath,
                openFlags: 0x00000002
            ),
            valve: denyValve
        )
        #expect(denyResp.lastResult == ES_AUTH_RESULT_DENY)
        #expect(denyResp.lastCache == false)

        let validToken = makeAuditToken(pid: mainPID, pidversion: 100, uid: 501)
        let (allowValve, allowResp) = EndpointSecurityTestSupport.makeTestValve(eventType: ES_EVENT_TYPE_AUTH_OPEN)
        manager.evaluateFileAuth(
            context: FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_OPEN,
                processPID: mainPID,
                processAuditToken: validToken,
                primaryPath: targetPath,
                openFlags: 0x00000002
            ),
            valve: allowValve
        )
        #expect(allowResp.lastResult == ES_AUTH_RESULT_ALLOW)
    }

    @Test("ESTamper blocks RENAME new-path, CLONE, and LINK targeting AppLocker.app and dynamic /Applications path")
    func tamperBlocksRenameNewPathCloneAndLinkInsideAppBundle() {
        let manager = ESManager(isTesting: true)
        manager.stateLock.withLock {
            _ = manager.protectedDynamicAppBundlePaths.insert("/Applications/Utilities/AppLocker.app")
        }

        let untrustedPID: pid_t = 88_777
        let untrustedToken = makeAuditToken(pid: untrustedPID, pidversion: 1, uid: 501)
        let vectors: [FileAuthEventContext] = [
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_RENAME,
                processPID: untrustedPID,
                processAuditToken: untrustedToken,
                primaryPath: "/tmp/evil_bin",
                isRenameToNewPath: true,
                renameNewDir: "/Applications/AppLocker.app/Contents/MacOS",
                renameNewFilename: "injected"
            ),
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_RENAME,
                processPID: untrustedPID,
                processAuditToken: untrustedToken,
                primaryPath: "/tmp/evil_bin",
                isRenameToNewPath: true,
                renameNewDir: "/Applications/Utilities/AppLocker.app/Contents",
                renameNewFilename: "Info.plist"
            ),
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_CLONE,
                processPID: untrustedPID,
                processAuditToken: untrustedToken,
                primaryPath: "/Applications/AppLocker.app/Contents/Resources",
                secondaryPath: "/tmp/evil_payload"
            ),
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_LINK,
                processPID: untrustedPID,
                processAuditToken: untrustedToken,
                primaryPath: "/Applications/Utilities/AppLocker.app/Contents/MacOS",
                secondaryPath: "/tmp/evil_payload"
            )
        ]

        for vector in vectors {
            let (valve, resp) = EndpointSecurityTestSupport.makeTestValve(eventType: vector.eventType)
            manager.evaluateFileAuth(context: vector, valve: valve)
            #expect(resp.lastResult == ES_AUTH_RESULT_DENY)
            #expect(resp.lastCache == false)
        }
    }

    @Test("isPathAllowedForUID blocks non-root root-folder tamper and restricts legacy config cleanup to main app")
    func isPathAllowedForUidHardensSharedRootAndLegacyConfig() {
        let manager = ESManager(isTesting: true)
        let mainPID: pid_t = 44_446
        manager.processIDLock.withLock {
            manager.authenticatedMainAppPID = mainPID
            manager.authenticatedMainAppPIDVersion = 200
        }
        let mainToken = makeAuditToken(pid: mainPID, pidversion: 200, uid: 501)

        // Even authenticated non-root main app cannot unlink /Users/Shared/AppLocker root or unknown non-UID paths
        for blockedPath in ["/Users/Shared/AppLocker", "/Users/Shared/AppLocker/arbitrary_file"] {
            let (valve, resp) = EndpointSecurityTestSupport.makeTestValve(eventType: ES_EVENT_TYPE_AUTH_UNLINK)
            manager.evaluateFileAuth(
                context: FileAuthEventContext(
                    eventType: ES_EVENT_TYPE_AUTH_UNLINK,
                    processPID: mainPID,
                    processAuditToken: mainToken,
                    primaryPath: blockedPath
                ),
                valve: valve
            )
            #expect(resp.lastResult == ES_AUTH_RESULT_DENY)
        }

        // Main app can still remove legacy /Users/Shared/AppLocker/config.plist during migration
        let (legacyAllowValve, legacyAllowResp) = EndpointSecurityTestSupport.makeTestValve(
            eventType: ES_EVENT_TYPE_AUTH_UNLINK
        )
        manager.evaluateFileAuth(
            context: FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_UNLINK,
                processPID: mainPID,
                processAuditToken: mainToken,
                primaryPath: "/Users/Shared/AppLocker/config.plist"
            ),
            valve: legacyAllowValve
        )
        #expect(legacyAllowResp.lastResult == ES_AUTH_RESULT_ALLOW)

        // Untrusted caller cannot remove legacy config.plist
        let untrustedToken = makeAuditToken(pid: 44_447, pidversion: 1, uid: 501)
        let (legacyDenyValve, legacyDenyResp) = EndpointSecurityTestSupport.makeTestValve(
            eventType: ES_EVENT_TYPE_AUTH_UNLINK
        )
        manager.evaluateFileAuth(
            context: FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_UNLINK,
                processPID: 44_447,
                processAuditToken: untrustedToken,
                primaryPath: "/Users/Shared/AppLocker/config.plist"
            ),
            valve: legacyDenyValve
        )
        #expect(legacyDenyResp.lastResult == ES_AUTH_RESULT_DENY)
    }

    @Test("ESManager startConfigMonitoring reloads configs from customBaseConfigDirectoryURL")
    func configMonitoringReloadsFromCustomDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLockerMonitorTest-\(UUID().uuidString)", isDirectory: true)
        let uidDir = tempDir.appendingPathComponent("501", isDirectory: true)
        try FileManager.default.createDirectory(at: uidDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ESManager(isTesting: true, baseConfigDirectoryURL: tempDir)
        manager.startConfigMonitoring()

        let store = ConfigStore(baseDirectoryURL: tempDir, userDefaults: .standard, uid: 501)
        let app = LockedAppConfig(
            bundleID: "com.test.hotreload",
            path: "/Applications/HotReload.app",
            name: "HotReload",
            cdhash: "00112233445566778899aabbccddeeff00112233"
        )
        store.save(apps: [app.path: app], isDisabled: false)

        let deadline = Date().addingTimeInterval(2.0)
        while manager.stateLock.withLock({ manager.lockedBundleIDs[501]?.contains("com.test.hotreload") != true }),
              Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        let isLoaded = manager.stateLock.withLock {
            manager.lockedBundleIDs[501]?.contains("com.test.hotreload") == true
        }
        #expect(isLoaded == true)
    }

    @Test("LockES.migrateApp preserves executable name from CFBundleExecutable")
    @MainActor
    func migrateAppPreservesExecutableName() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLockerMigrateTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let suiteName = "com.TranPhuong319.MigrateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let renamedBundle = tempDir.appendingPathComponent("RenamedApp.app", isDirectory: true)
        let contents = renamedBundle.appendingPathComponent("Contents", isDirectory: true)
        let macOSDir = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.example.renamed",
            "CFBundleExecutable": "ActualBinary",
            "CFBundleName": "RenamedApp"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        try Data("#!/bin/sh\n".utf8).write(to: macOSDir.appendingPathComponent("ActualBinary"))

        let store = ConfigStore(baseDirectoryURL: tempDir, userDefaults: defaults, uid: 501)
        let lockManager = LockES(configStore: store)
        let oldPath = tempDir.appendingPathComponent("OldApp.app").path
        lockManager.lockedApps[oldPath] = LockedAppConfig(
            bundleID: "com.example.renamed",
            path: oldPath,
            execFile: "ActualBinary",
            name: "OldApp",
            cdhash: "deadbeef"
        )
        lockManager.migrateApp(from: oldPath, to: renamedBundle.path)
        #expect(lockManager.lockedApps[renamedBundle.path]?.execFile == "ActualBinary")
        #expect(lockManager.lockedApps[renamedBundle.path]?.cdhash == "deadbeef")
    }

    @Test("Batch upgrade approval records grace period timestamp")
    @MainActor
    func batchUpgradeApprovalRecordsGraceTimestamp() async {
        let coordinator = AuthCoordinator()
        coordinator.dependencies.isBatchWindowVisible = { false }
        coordinator.dependencies.showBatchWindow = {}
        coordinator.dependencies.hideBatchWindow = {}
        coordinator.dependencies.sendBlockedNotification = { _ in }
        coordinator.dependencies.cancelAuth = {}
        coordinator.dependencies.refreshWatchdog = { _ in }
        coordinator.dependencies.processPendingApps = { _, _, _ in }
        coordinator.dependencies.sleep = { _ in await Task.yield() }

        let authStarted: CheckedContinuation<Bool, Error> = await withCheckedContinuation { startCont in
            coordinator.dependencies.authenticate = { _ in
                try await withCheckedThrowingContinuation { authCont in
                    startCont.resume(returning: authCont)
                }
            }
            coordinator.addPendingAuth(name: "AppA", path: "/Applications/AppA.app", cdhash: "h1", pid: 9001)
            coordinator.processIncomingQueue()
        }

        coordinator.addPendingAuth(name: "AppB", path: "/Applications/AppB.app", cdhash: "h2", pid: 9002)
        #expect(coordinator.isUpgradingToBatch == true)
        authStarted.resume(returning: true)
        await Task.yield()
        #expect(coordinator.lastAuthTimestampsByPath["/Applications/AppA.app"] != nil)
    }
}
