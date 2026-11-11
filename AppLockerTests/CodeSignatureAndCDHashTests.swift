//
//  CodeSignatureAndCDHashTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 4/11/26.
//

import Darwin
import EndpointSecurity
import Foundation
import Testing

@Suite("Self-Signed Code Signature & CDHash Tests", .serialized)
struct CodeSignatureAndCDHashTests {

    private static let selfSignedCertSHA1 = "DE0CAD38FCD90BF4E60BD946A23C9C13DEA878F8"

    private func compileAndSignHelperBinary(
        identifier: String,
        signIdentity: String
    ) throws -> (binaryURL: URL, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLockerSigTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let sourceURL = tempDir.appendingPathComponent("helper.c")
        let binaryURL = tempDir.appendingPathComponent("helper_bin")
        let cSource = """
        #include <unistd.h>
        int main(void) {
            sleep(5);
            return 0;
        }
        """
        try cSource.write(to: sourceURL, atomically: true, encoding: .utf8)

        let clang = Process()
        clang.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        clang.arguments = ["-O0", sourceURL.path, "-o", binaryURL.path]
        try clang.run()
        clang.waitUntilExit()
        #expect(clang.terminationStatus == 0)

        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = [
            "--force",
            "--sign", signIdentity,
            "--identifier", identifier,
            binaryURL.path
        ]
        try codesign.run()
        codesign.waitUntilExit()
        #expect(codesign.terminationStatus == 0)

        return (binaryURL, tempDir)
    }

    private func spawnAndFetchAuditToken(binaryURL: URL) throws -> (Process, audit_token_t) {
        let proc = Process()
        proc.executableURL = binaryURL
        try proc.run()

        let pid = proc.processIdentifier
        var taskName: mach_port_name_t = 0
        let krTask = task_name_for_pid(mach_task_self_, pid, &taskName)
        #expect(krTask == KERN_SUCCESS)
        defer {
            if taskName != 0 {
                mach_port_deallocate(mach_task_self_, taskName)
            }
        }

        var token = audit_token_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size
        )
        let krInfo = withUnsafeMutablePointer(to: &token) { tokenPtr in
            tokenPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(taskName, task_flavor_t(TASK_AUDIT_TOKEN), intPtr, &count)
            }
        }
        #expect(krInfo == KERN_SUCCESS)
        return (proc, token)
    }

    @Test("Binary signed with DE0CAD38... + com.TranPhuong319.AppLocker passes both requirements")
    func mainAppSignedBinaryPassesBothRequirements() throws {
        let (binaryURL, tempDir) = try compileAndSignHelperBinary(
            identifier: "com.TranPhuong319.AppLocker",
            signIdentity: Self.selfSignedCertSHA1
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (proc, token) = try spawnAndFetchAuditToken(binaryURL: binaryURL)
        defer {
            kill(proc.processIdentifier, SIGKILL)
            proc.waitUntilExit()
        }

        let passesMainApp = CodeSignatureValidator.validate(
            auditToken: token,
            requirement: CodeSignatureValidator.mainAppRequirement
        )
        let passesProjectRoot = CodeSignatureValidator.validate(
            auditToken: token,
            requirement: CodeSignatureValidator.projectRootRequirement
        )

        #expect(passesMainApp == true)
        #expect(passesProjectRoot == true)
    }

    @Test("Binary signed with DE0CAD38... + com.TranPhuong319.Helper fails mainAppRequirement but passes projectRoot")
    func helperSignedBinaryFailsMainAppButPassesProjectRoot() throws {
        let (binaryURL, tempDir) = try compileAndSignHelperBinary(
            identifier: "com.TranPhuong319.Helper",
            signIdentity: Self.selfSignedCertSHA1
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (proc, token) = try spawnAndFetchAuditToken(binaryURL: binaryURL)
        defer {
            kill(proc.processIdentifier, SIGKILL)
            proc.waitUntilExit()
        }

        let passesMainApp = CodeSignatureValidator.validate(
            auditToken: token,
            requirement: CodeSignatureValidator.mainAppRequirement
        )
        let passesProjectRoot = CodeSignatureValidator.validate(
            auditToken: token,
            requirement: CodeSignatureValidator.projectRootRequirement
        )

        #expect(passesMainApp == false)
        #expect(passesProjectRoot == true)
    }

    @Test("Ad-hoc signed binary (--sign -) fails both mainAppRequirement and projectRootRequirement")
    func adHocSignedBinaryFailsBothRequirements() throws {
        let (binaryURL, tempDir) = try compileAndSignHelperBinary(
            identifier: "com.TranPhuong319.AppLocker",
            signIdentity: "-"
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (proc, token) = try spawnAndFetchAuditToken(binaryURL: binaryURL)
        defer {
            kill(proc.processIdentifier, SIGKILL)
            proc.waitUntilExit()
        }

        let passesMainApp = CodeSignatureValidator.validate(
            auditToken: token,
            requirement: CodeSignatureValidator.mainAppRequirement
        )
        let passesProjectRoot = CodeSignatureValidator.validate(
            auditToken: token,
            requirement: CodeSignatureValidator.projectRootRequirement
        )

        #expect(passesMainApp == false)
        #expect(passesProjectRoot == false)
    }

    @Test("cdHash(for:) extracts 40-char hex CDHash matching /usr/bin/codesign -dvvv output")
    func cdHashExtractionMatchesCodesignOutput() throws {
        let (binaryURL, tempDir) = try compileAndSignHelperBinary(
            identifier: "com.TranPhuong319.AppLocker",
            signIdentity: Self.selfSignedCertSHA1
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let extractedHash = try #require(cdHash(for: binaryURL.path))
        #expect(extractedHash.count == 40)

        let pipe = Pipe()
        let codesignInfo = Process()
        codesignInfo.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesignInfo.arguments = ["-dvvv", binaryURL.path]
        codesignInfo.standardError = pipe
        try codesignInfo.run()
        codesignInfo.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let outputString = String(data: outputData, encoding: .utf8) ?? ""
        #expect(outputString.lowercased().contains("cdhash=\(extractedHash.lowercased())"))
    }
}

// MARK: - Adversarial Spoofing, Config/UserDefaults Tampering & XPC PID Recycling Matrix

@Suite("Adversarial Security & Tamper Matrix Tests", .serialized)
struct AdversarialSecurityMatrixTests {
    @Test("Spoofed updater or installer without root certificate is denied overwriting AppLocker.app or ESExtension")
    func spoofedUpdaterDeniedOverwritingAppAndSystemExtension() {
        let manager = ESManager(isTesting: true)
        let fakeUpdaterPID: pid_t = 66_666
        var fakeToken = audit_token_t()
        fakeToken.val.5 = UInt32(bitPattern: fakeUpdaterPID)
        let sysExtBinary = "/Applications/AppLocker.app/Contents/Library/SystemExtensions/"
            + "com.TranPhuong319.AppLocker.ESExtension.systemextension/Contents/MacOS/ESExtension"

        let attackVectors: [FileAuthEventContext] = [
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_RENAME, processPID: fakeUpdaterPID,
                processAuditToken: fakeToken, signingID: "org.sparkle-project.Sparkle.Autoupdate",
                primaryPath: "/tmp/SpoofedUpdate/AppLocker.app", isRenameToNewPath: true,
                renameNewDir: "/Applications", renameNewFilename: "AppLocker.app"
            ),
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_RENAME, processPID: fakeUpdaterPID,
                processAuditToken: fakeToken, signingID: "com.TranPhuong319.AppLocker",
                primaryPath: "/tmp/SpoofedUpdate/AppLocker.app",
                secondaryPath: "/Applications/AppLocker.app", isRenameToNewPath: false
            ),
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_UNLINK, processPID: fakeUpdaterPID,
                processAuditToken: fakeToken, signingID: "com.TranPhuong319.AppLocker",
                primaryPath: sysExtBinary
            ),
            FileAuthEventContext(
                eventType: ES_EVENT_TYPE_AUTH_OPEN, processPID: fakeUpdaterPID,
                processAuditToken: fakeToken, signingID: "com.TranPhuong319.AppLocker",
                primaryPath: sysExtBinary, openFlags: 0x00000002 | Int32(O_TRUNC)
            )
        ]

        for vector in attackVectors {
            let responder = MockAuthResponder()
            manager.evaluateFileAuth(context: vector, valve: responder)
            #expect(responder.callCount == 1)
            #expect(responder.lastResult == ES_AUTH_RESULT_DENY)
            #expect(responder.lastCache == false)
        }
    }

    @Test("Spoofed AppLocker binary with fake signingID fails self-execution exemption and gets blocked")
    func spoofedAppLockerSelfExecutionDeniedAndBlocked() throws {
        let (childProc, tempDir) = try EndpointSecurityTestSupport.spawnTemporarySleepProcess()
        let childPID = childProc.processIdentifier
        defer {
            kill(childPID, SIGKILL)
            kill(childPID, SIGCONT)
            childProc.waitUntilExit()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let realToken = try #require(EndpointSecurityTestSupport.realAuditToken(for: childPID))
        let uid = audit_token_to_euid(realToken)
        let manager = ESManager(isTesting: true)

        #expect(manager.isAppLockerSelfExecution(
            signingID: "com.TranPhuong319.AppLocker", token: realToken, pid: childPID
        ) == false)

        let fakeHashData = Data(repeating: 0xBB, count: 20)
        let fakeHashHex = fakeHashData.hexEncodedString
        manager.stateLock.withLock { manager.lockedCDHashes[uid] = [fakeHashHex] }

        let execCtx = ExecEventContext(
            targetPID: childPID, targetAuditToken: realToken, uid: uid,
            path: tempDir.appendingPathComponent("sleep_test_bin").path,
            signingID: "com.TranPhuong319.AppLocker", cdhashData: fakeHashData, cdhashHex: fakeHashHex
        )
        #expect(manager.evaluateNotifyExec(context: execCtx) == true)
        #expect(manager.isPendingVerification(pid: childPID) == true)
    }

    @Test("Config.plist corruption, isDisabled sync, UserDefaults isolation, and Multi-UID / Telephony spoof checks")
    @MainActor
    func configTamperingUserDefaultsIsolationAndMultiUidMatrix() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLockerAdvConfig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let suiteName = "com.TranPhuong319.AdvTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let (uidA, uidB): (uid_t, uid_t) = (501, 502)
        // 1. Corrupted binary plist fails closed without crashing
        let corruptURL = UserConfig.configURL(for: 999, baseDirectoryURL: tempDir)
        try FileManager.default.createDirectory(
            at: corruptURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("CORRUPT_BINARY_PLIST_0xDEAD".utf8).write(to: corruptURL)
        #expect(UserConfig.load(for: 999, baseDirectoryURL: tempDir) == nil)

        // 2. Save valid config for uidA (active) and uidB (disabled)
        let lockedApp = LockedAppConfig(
            bundleID: "com.apple.Notes", path: "/System/Applications/Notes.app",
            name: "Notes", cdhash: "1122334455667788990011223344556677889900"
        )
        let storeA = ConfigStore(baseDirectoryURL: tempDir, userDefaults: defaults, uid: uidA)
        storeA.save(apps: [lockedApp.path: lockedApp], isDisabled: false, autoLockTimeoutMinutes: 10)
        let storeB = ConfigStore(baseDirectoryURL: tempDir, userDefaults: defaults, uid: uidB)
        storeB.save(apps: [lockedApp.path: lockedApp], isDisabled: true, allowIncomingCalls: false)

        // 3. Tamper with UserDefaults keys -> ESManager & ConfigStore remain unaffected
        defaults.set(false, forKey: "isExtensionInstalled")
        defaults.set(true, forKey: "isDisabled")
        defaults.set(999_999, forKey: "autoLockTimeoutMinutes")
        defaults.set(-500, forKey: "batchAuthCountdownSeconds")
        #expect(storeA.load().isDisabled == false && storeA.load().autoLockTimeoutMinutes == 10)

        verifyMultiUidAndTelephonySpoof(tempDir: tempDir, uidA: uidA, uidB: uidB, defaults: defaults)
    }

    @MainActor
    private func verifyMultiUidAndTelephonySpoof(
        tempDir: URL, uidA: uid_t, uidB: uid_t, defaults: UserDefaults
    ) {
        let manager = ESManager(isTesting: true, baseConfigDirectoryURL: tempDir)
        manager.loadInitialConfigSync()
        let hashHex = "1122334455667788990011223344556677889900"
        let notesExec = "/System/Applications/Notes.app/Contents/MacOS/Notes"
        #expect(manager.isProcessBlocked(
            path: notesExec, cdhashData: Data(repeating: 0x11, count: 20),
            cdhashHex: hashHex, signingID: "com.apple.Notes", uid: uidA
        ) == true)
        #expect(manager.isProcessBlocked(
            path: notesExec, cdhashData: Data(repeating: 0x11, count: 20),
            cdhashHex: hashHex, signingID: "com.apple.Notes", uid: uidB
        ) == false)

        manager.stateLock.withLock { manager.isIncomingCallActive = true }
        manager.telephonySignatureValidator = { _ in false }
        #expect(manager.isAllowedIncomingCall(
            signingID: "com.apple.FaceTime", path: "/tmp/FakeFaceTime.app/Contents/MacOS/FaceTime", uid: uidA
        ) == false)

        let coordinator = AuthCoordinator()
        coordinator.dependencies.userDefaults = defaults
        coordinator.dependencies.refreshWatchdog = { _ in }
        coordinator.dependencies.sleep = { _ in try await Task.sleep(for: .seconds(3600)) }
        coordinator.startOrResetCountdownTimer()
        #expect(coordinator.remainingSeconds == 30)
        coordinator.stopCountdownTimer()

        // 4. Verify ESTamper enforces per-UID isolation even for an authenticated Main App PID (with 0o777 folders)
        let authPID: pid_t = 44_444
        var tokenUIDA = audit_token_t()
        tokenUIDA.val.1 = uidA // euid = 501
        tokenUIDA.val.5 = UInt32(bitPattern: authPID)
        manager.processIDLock.withLock { manager.authenticatedMainAppPID = authPID }

        let ownWriteCtx = FileAuthEventContext(
            eventType: ES_EVENT_TYPE_AUTH_OPEN, processPID: authPID, processAuditToken: tokenUIDA,
            primaryPath: "/Users/Shared/AppLocker/\(uidA)/config.plist", openFlags: 0x00000002
        )
        let ownWriteResp = MockAuthResponder()
        manager.evaluateFileAuth(context: ownWriteCtx, valve: ownWriteResp)
        #expect(ownWriteResp.lastResult == ES_AUTH_RESULT_ALLOW)

        let crossUidUnlinkCtx = FileAuthEventContext(
            eventType: ES_EVENT_TYPE_AUTH_UNLINK, processPID: authPID, processAuditToken: tokenUIDA,
            primaryPath: "/Users/Shared/AppLocker/\(uidB)/config.plist"
        )
        let crossUidUnlinkResp = MockAuthResponder()
        manager.evaluateFileAuth(context: crossUidUnlinkCtx, valve: crossUidUnlinkResp)
        #expect(crossUidUnlinkResp.lastResult == ES_AUTH_RESULT_DENY)
    }
}
