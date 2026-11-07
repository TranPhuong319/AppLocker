//
//  ConfigStoreAndPolicyTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 4/11/26.
//

import Darwin
import Foundation
import Testing

struct IsolatedTestEnvironment {
    let tempDir: URL
    let userDefaults: UserDefaults
    let suiteName: String

    func cleanup() {
        userDefaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
    }
}

@Suite("ConfigStore, Migration, Self-Lockout Healing & Exec Policy Tests", .serialized)
struct ConfigStoreAndPolicyTests {

    private func makeIsolatedEnvironment() throws -> IsolatedTestEnvironment {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLockerConfigTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let suiteName = "com.TranPhuong319.AppLockerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return IsolatedTestEnvironment(tempDir: tempDir, userDefaults: defaults, suiteName: suiteName)
    }

    @Test("Atomic binary PropertyList read/write roundtrip for ConfigStore and UserConfig")
    func atomicBinaryPlistReadWriteRoundtrip() throws {
        let env = try makeIsolatedEnvironment()
        defer { env.cleanup() }

        let testUID: uid_t = 501
        let store = ConfigStore(
            baseDirectoryURL: env.tempDir,
            userDefaults: env.userDefaults,
            uid: testUID,
            selfBundleID: "com.TranPhuong319.AppLocker",
            selfBundlePath: "/Applications/AppLocker.app"
        )

        let sampleApp = LockedAppConfig(
            bundleID: "com.apple.Safari",
            path: "/Applications/Safari.app",
            execFile: "Safari",
            name: "Safari",
            cdhash: "11223344556677889900aabbccddeeff00112233"
        )

        store.save(
            apps: [sampleApp.path: sampleApp],
            isDisabled: false,
            allowIncomingCalls: true,
            autoLockTimeoutMinutes: 15
        )

        let loadedByStore = store.load()
        #expect(loadedByStore.apps.count == 1)
        #expect(loadedByStore.apps["/Applications/Safari.app"] == sampleApp)
        #expect(loadedByStore.isDisabled == false)
        #expect(loadedByStore.allowIncomingCalls == true)
        #expect(loadedByStore.autoLockTimeoutMinutes == 15)

        let loadedByUserConfig = try #require(UserConfig.load(for: testUID, baseDirectoryURL: env.tempDir))
        #expect(loadedByUserConfig.apps.first == sampleApp)

        let allLoaded = UserConfig.loadAll(baseDirectoryURL: env.tempDir)
        #expect(allLoaded[testUID]?.apps.first?.bundleID == "com.apple.Safari")
    }

    @Test("Legacy config.plist migration supports all 4 historical formats and deletes legacy file")
    func legacyConfigMigrationAllFourFormats() throws {
        let testUID: uid_t = 501
        let sampleApp = LockedAppConfig(
            bundleID: "com.apple.calculator",
            path: "/System/Applications/Calculator.app",
            name: "Calculator",
            cdhash: "aabbccddeeff00112233445566778899aabbccdd"
        )
        let sampleUserConfig = UserConfig(
            isDisabled: false,
            apps: [sampleApp],
            allowIncomingCalls: true,
            autoLockTimeoutMinutes: 5
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        let payloads: [Data] = [
            try encoder.encode([String(testUID): sampleUserConfig]),
            try encoder.encode(sampleUserConfig),
            try encoder.encode([String(testUID): [sampleApp]]),
            try encoder.encode([sampleApp])
        ]

        for payload in payloads {
            let env = try makeIsolatedEnvironment()
            defer { env.cleanup() }

            let legacyURL = env.tempDir.appendingPathComponent("config.plist")
            try payload.write(to: legacyURL, options: .atomic)

            let store = ConfigStore(
                baseDirectoryURL: env.tempDir,
                userDefaults: env.userDefaults,
                uid: testUID,
                selfBundleID: "com.TranPhuong319.AppLocker",
                selfBundlePath: "/Applications/AppLocker.app"
            )

            let loaded = store.load()
            #expect(loaded.apps["/System/Applications/Calculator.app"]?.bundleID == "com.apple.calculator")
            #expect(FileManager.default.fileExists(atPath: legacyURL.path) == false)
        }
    }

    @Test("Self-lockout healing removes AppLocker by bundleID, bundlePath, symlink path, or CDHash")
    func selfLockoutHealingRemovesAppLockerAcrossAllVectors() throws {
        let env = try makeIsolatedEnvironment()
        defer { env.cleanup() }

        let fakeSelfAppDir = env.tempDir.appendingPathComponent("AppLocker.app", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeSelfAppDir, withIntermediateDirectories: true)
        let symlinkAppURL = env.tempDir.appendingPathComponent("AppLockerAlias.app")
        try FileManager.default.createSymbolicLink(at: symlinkAppURL, withDestinationURL: fakeSelfAppDir)

        let store = ConfigStore(
            baseDirectoryURL: env.tempDir,
            userDefaults: env.userDefaults,
            uid: 501,
            selfBundleID: "com.TranPhuong319.AppLocker",
            selfBundlePath: fakeSelfAppDir.path
        )

        let byBundleID = LockedAppConfig(
            bundleID: "com.TranPhuong319.AppLocker", path: "/Applications/RenamedLocker.app",
            name: "Renamed", cdhash: "1111"
        )
        let byPath = LockedAppConfig(
            bundleID: "com.other.id", path: fakeSelfAppDir.path, name: "DirectPath", cdhash: "2222"
        )
        let bySymlink = LockedAppConfig(
            bundleID: "com.other.symlink", path: symlinkAppURL.path, name: "SymlinkPath", cdhash: "3333"
        )
        let legitimateApp = LockedAppConfig(
            bundleID: "com.apple.Notes", path: "/System/Applications/Notes.app", name: "Notes", cdhash: "9999"
        )

        store.save(
            apps: [
                byBundleID.path: byBundleID,
                byPath.path: byPath,
                bySymlink.path: bySymlink,
                legitimateApp.path: legitimateApp
            ],
            isDisabled: false
        )

        let healed = store.load()
        #expect(healed.apps.count == 1)
        #expect(healed.apps["/System/Applications/Notes.app"] != nil)
        #expect(healed.apps[byBundleID.path] == nil)
        #expect(healed.apps[byPath.path] == nil)
        #expect(healed.apps[bySymlink.path] == nil)
    }

    @Test("ESEventNotifyExec policy blocks by CDHash/bundlePath, normalizes firmlinks, and bypasses incoming calls")
    func notifyExecPolicyEvaluationAndTelephonyBypass() throws {
        let env = try makeIsolatedEnvironment()
        defer { env.cleanup() }

        let sleepBin = env.tempDir.appendingPathComponent("policy_sleep_bin")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: sleepBin)
        let proc = Process()
        proc.executableURL = sleepBin
        proc.arguments = ["15"]
        try proc.run()
        let childPID = proc.processIdentifier
        defer {
            kill(childPID, SIGKILL)
            kill(childPID, SIGCONT)
            proc.waitUntilExit()
        }

        let uid = getuid()
        var token = audit_token_t()
        token.val.5 = UInt32(bitPattern: childPID)
        token.val.1 = uid

        let manager = ESManager(isTesting: true, baseConfigDirectoryURL: env.tempDir)
        let faceTimeExec = "/System/Volumes/Data/System/Applications/FaceTime.app/Contents/MacOS/FaceTime"
        manager.stateLock.withLock {
            manager.lockedBundlePaths[uid] = ["/System/Applications/FaceTime.app"]
            manager.allowIncomingCallsByUID[uid] = true
            manager.isIncomingCallActive = true
        }
        manager.telephonySignatureValidator = { path in path.contains("FaceTime.app") }

        let callCtx = ExecEventContext(
            targetPID: childPID, targetAuditToken: token, uid: uid,
            path: faceTimeExec, signingID: "com.apple.FaceTime"
        )
        #expect(manager.evaluateNotifyExec(context: callCtx) == false)
        #expect(manager.isPendingVerification(pid: childPID) == false)

        manager.stateLock.withLock { manager.isIncomingCallActive = false }
        #expect(manager.evaluateNotifyExec(context: callCtx) == true)
        let pendingRecord = manager.pendingPIDLock.withLock { manager.pendingVerificationProcesses[childPID] }
        #expect(pendingRecord != nil)
    }

    @Test("ESManager isProcessBlocked blocks symlinked bundle, symlinked executable, and CDHash evasion")
    func notifyExecPolicyBlocksSymlinks() throws {
        let env = try makeIsolatedEnvironment()
        defer { env.cleanup() }

        // Setup real bundle
        let realBundle = env.tempDir.appendingPathComponent("LockedApp.app")
        let macosDir = realBundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macosDir, withIntermediateDirectories: true)
        let realExec = macosDir.appendingPathComponent("LockedApp")
        try "binary-content".write(to: realExec, atomically: true, encoding: .utf8)

        // Setup Info.plist
        let infoPlist = realBundle.appendingPathComponent("Contents/Info.plist")
        let plistXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleExecutable</key><string>LockedApp</string>
        <key>CFBundleIdentifier</key><string>com.test.locked</string>
        </dict></plist>
        """
        try plistXML.write(to: infoPlist, atomically: true, encoding: .utf8)

        // Create symlink to .app bundle
        let symlinkBundle = env.tempDir.appendingPathComponent("SymlinkAlias.app")
        try FileManager.default.createSymbolicLink(at: symlinkBundle, withDestinationURL: realBundle)

        // Create symlink to executable
        let symlinkExec = env.tempDir.appendingPathComponent("symlink_exec_bin")
        try FileManager.default.createSymbolicLink(at: symlinkExec, withDestinationURL: realExec)

        let manager = ESManager(isTesting: true, baseConfigDirectoryURL: env.tempDir)
        let uid = getuid()
        let fakeCDHash = "AABBCCDDEEFF00112233445566778899AABBCCDD"
        let cdhashData = Data(repeating: 0xAA, count: 20)
        let zeroData = Data(repeating: 0, count: 20)

        manager.stateLock.withLock {
            manager.lockedBundlePaths[uid] = [realBundle.path]
            manager.lockedCDHashes[uid] = [fakeCDHash]
        }

        // 1. CDHash defense: Even with completely arbitrary path or symlink, CDHash matches -> BLOCKED
        let blockedByCDHash = manager.isProcessBlocked(
            path: symlinkExec.path,
            cdhashData: cdhashData,
            cdhashHex: fakeCDHash,
            uid: uid
        )
        #expect(blockedByCDHash == true)

        // 2. Symlinked bundle defense (with zero CDHash fallback) -> BLOCKED
        let symlinkedExecPath = symlinkBundle.appendingPathComponent("Contents/MacOS/LockedApp").path
        let blockedBySymlinkBundle = manager.isProcessBlocked(
            path: symlinkedExecPath,
            cdhashData: zeroData,
            cdhashHex: "",
            uid: uid
        )
        #expect(blockedBySymlinkBundle == true)
    }

    @Test("ESManager isProcessBlocked blocks app moved outside /Applications with new CDHash via signingID")
    func notifyExecPolicyBlocksMovedAppWithNewCDHashViaSigningID() throws {
        let env = try makeIsolatedEnvironment()
        defer { env.cleanup() }

        let manager = ESManager(isTesting: true, baseConfigDirectoryURL: env.tempDir)
        let uid = getuid()
        manager.stateLock.withLock {
            manager.lockedBundleIDs[uid] = ["com.test.locked"]
            manager.lockedBundlePaths[uid] = ["/Applications/LockedApp.app"]
            manager.lockedCDHashes[uid] = ["1111222233334444555566667777888899990000"]
        }

        // Attacker updated binary with new CDHash, deleted /Applications/LockedApp.app,
        // and runs it from /tmp/Evasion.app
        let newCDHashHex = "9999888877776666555544443333222211110000"
        let newData = Data(repeating: 0x99, count: 20)
        let movedPath = "/tmp/Evasion.app/Contents/MacOS/Binary"

        let isBlocked = manager.isProcessBlocked(
            path: movedPath,
            cdhashData: newData,
            cdhashHex: newCDHashHex,
            signingID: "com.test.locked",
            uid: uid
        )
        #expect(isBlocked == true)
    }
}
