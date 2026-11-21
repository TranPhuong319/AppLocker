//
//  AppDirectoryPolicyTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 20/11/26.
//

import Foundation
import Testing

@Suite("App Directory & Relocation Policy Tests")
struct AppDirectoryPolicyTests {

    // MARK: - Location Validation

    @Test("Allows bundles directly inside /Applications and its subdirectories")
    func allowsApplicationsAndSubdirectories() {
        let direct = URL(fileURLWithPath: "/Applications/AppLocker.app")
        let nested = URL(fileURLWithPath: "/Applications/Utilities/AppLocker.app")

        #expect(AppDirectoryPolicy.isAllowedLocation(for: direct))
        #expect(AppDirectoryPolicy.isAllowedLocation(for: nested))
        #expect(AppDirectoryPolicy.isAllowedLocation(for: direct, allowedDirectories: ["/Applications/"]))
    }

    @Test("Rejects sibling paths sharing /Applications prefix and external folders")
    func rejectsPrefixSpoofingAndExternalLocations() {
        let siblingBackup = URL(fileURLWithPath: "/ApplicationsBackup/AppLocker.app")
        let siblingNumeric = URL(fileURLWithPath: "/Applications2/AppLocker.app")
        let downloads = URL(fileURLWithPath: "/Users/test/Downloads/AppLocker.app")
        let dmgVolume = URL(fileURLWithPath: "/Volumes/AppLocker/AppLocker.app")
        let traversal = URL(fileURLWithPath: "/Applications/../tmp/AppLocker.app")

        #expect(!AppDirectoryPolicy.isAllowedLocation(for: siblingBackup))
        #expect(!AppDirectoryPolicy.isAllowedLocation(for: siblingNumeric))
        #expect(!AppDirectoryPolicy.isAllowedLocation(for: downloads))
        #expect(!AppDirectoryPolicy.isAllowedLocation(for: dmgVolume))
        #expect(!AppDirectoryPolicy.isAllowedLocation(for: traversal))
    }

    // MARK: - Display Path Formatting

    @Test("Abbreviates long paths with more than four components while keeping short paths intact")
    func abbreviatesLongPathsOnly() {
        let shortBundle = URL(fileURLWithPath: "/tmp/AppLocker.app")
        #expect(AppDirectoryPolicy.abbreviatedDisplayPath(for: shortBundle) == "/tmp")

        let longBundle = URL(
            fileURLWithPath: "/Volumes/ExternalDrive/FolderOne/FolderTwo/FolderThree/FolderFour/AppLocker.app"
        )
        let abbreviated = AppDirectoryPolicy.abbreviatedDisplayPath(for: longBundle)
        #expect(abbreviated == "/Volumes/.../FolderThree/FolderFour")
    }

    // MARK: - FileManager Relocation

    @Test("Relocates bundle via FileManager when target directory is writable")
    func relocatesViaFileManagerSuccessfully() throws {
        let sandbox = try makeTempSandbox()
        defer { cleanupSandbox(sandbox) }

        let source = sandbox.appendingPathComponent("Source/AppLocker.app")
        let targetDir = sandbox.appendingPathComponent("Applications")
        try createMockBundle(at: source, marker: "v2")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        var trashedURL: URL?
        var scriptInvoked = false

        let result = AppDirectoryPolicy.relocate(
            from: source,
            to: targetDir,
            trashSource: { url in
                trashedURL = url
                try FileManager.default.removeItem(at: url)
            },
            runPrivilegedScript: { _ in
                scriptInvoked = true
                return nil
            }
        )

        let expectedDest = AppDirectoryPolicy.destinationURL(for: source, in: targetDir)
        #expect(result == .relocatedViaFileManager(destination: expectedDest, trashErrorDescription: nil))
        #expect(!scriptInvoked)
        #expect(trashedURL == source)
        #expect(try readMarker(in: expectedDest) == "v2")
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Replaces existing destination atomically and leaves no staging directories")
    func replacesExistingBundleViaFileManager() throws {
        let sandbox = try makeTempSandbox()
        defer { cleanupSandbox(sandbox) }

        let source = sandbox.appendingPathComponent("Source/AppLocker.app")
        let targetDir = sandbox.appendingPathComponent("Applications")
        let existingDest = AppDirectoryPolicy.destinationURL(for: source, in: targetDir)
        try createMockBundle(at: source, marker: "new-version")
        try createMockBundle(at: existingDest, marker: "old-version")

        let result = AppDirectoryPolicy.relocate(
            from: source,
            to: targetDir,
            trashSource: { try FileManager.default.removeItem(at: $0) },
            runPrivilegedScript: { _ in
                Issue.record("Privileged script should not be called when FileManager succeeds")
                return nil
            }
        )

        #expect(result == .relocatedViaFileManager(destination: existingDest, trashErrorDescription: nil))
        #expect(try readMarker(in: existingDest) == "new-version")

        let entries = try FileManager.default.contentsOfDirectory(atPath: targetDir.path)
        #expect(entries == ["AppLocker.app"])
    }

    @Test("Treats trash failure on read-only source as non-fatal after successful copy")
    func trashFailureIsNonFatal() throws {
        let sandbox = try makeTempSandbox()
        defer { cleanupSandbox(sandbox) }

        let source = sandbox.appendingPathComponent("DMG/AppLocker.app")
        let targetDir = sandbox.appendingPathComponent("Applications")
        try createMockBundle(at: source, marker: "dmg-build")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let simulatedError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteVolumeReadOnlyError,
            userInfo: [NSLocalizedDescriptionKey: "Read-only volume"]
        )

        let result = AppDirectoryPolicy.relocate(
            from: source,
            to: targetDir,
            trashSource: { _ in throw simulatedError },
            runPrivilegedScript: { _ in nil }
        )

        let expectedDest = AppDirectoryPolicy.destinationURL(for: source, in: targetDir)
        #expect(
            result == .relocatedViaFileManager(
                destination: expectedDest,
                trashErrorDescription: "Read-only volume"
            )
        )
        #expect(try readMarker(in: expectedDest) == "dmg-build")
    }

    @Test("Preserves existing destination when copy fails and falls back to privileged script")
    func preservesExistingBundleOnCopyFailure() throws {
        let sandbox = try makeTempSandbox()
        defer { cleanupSandbox(sandbox) }

        let missingSource = sandbox.appendingPathComponent("Missing/AppLocker.app")
        let targetDir = sandbox.appendingPathComponent("Applications")
        let existingDest = targetDir.appendingPathComponent("AppLocker.app")
        try createMockBundle(at: existingDest, marker: "keep-me")

        var capturedScript: String?
        let result = AppDirectoryPolicy.relocate(
            from: missingSource,
            to: targetDir,
            trashSource: { _ in },
            runPrivilegedScript: { script in
                capturedScript = script
                return "User canceled"
            }
        )

        guard case let .failed(_, scriptError) = result else {
            Issue.record("Expected relocation to fail when both FileManager and script fail")
            return
        }
        #expect(scriptError == "User canceled")
        #expect(capturedScript?.contains("with administrator privileges") == true)
        #expect(try readMarker(in: existingDest) == "keep-me")
    }

    @Test("Falls back to privileged script and reports success when script returns nil")
    func fallsBackToPrivilegedScriptSuccessfully() throws {
        let sandbox = try makeTempSandbox()
        defer { cleanupSandbox(sandbox) }

        let missingSource = sandbox.appendingPathComponent("Source/AppLocker.app")
        let targetDir = sandbox.appendingPathComponent("Applications")
        let expectedDest = targetDir.appendingPathComponent("AppLocker.app")

        let result = AppDirectoryPolicy.relocate(
            from: missingSource,
            to: targetDir,
            trashSource: { _ in },
            runPrivilegedScript: { _ in nil }
        )

        guard case let .relocatedViaPrivilegedScript(destination, fileManagerError) = result else {
            Issue.record("Expected privileged script fallback success")
            return
        }
        #expect(destination == expectedDest)
        #expect(!fileManagerError.isEmpty)
    }
}

extension AppDirectoryPolicyTests {
    // MARK: - Privileged Shell Command Safety

    @Test("Shell quoting safely neutralizes quotes, spaces, backticks, and command substitution")
    func privilegedShellCommandResistsInjection() throws {
        let sandbox = try makeTempSandbox()
        defer { cleanupSandbox(sandbox) }

        let markerFile = sandbox.appendingPathComponent("pwned")
        let hostileDirName = "Dir 'with' \"quotes\" $(touch \(markerFile.path)) `touch \(markerFile.path)`"
        let source = sandbox
            .appendingPathComponent(hostileDirName)
            .appendingPathComponent("AppLocker.app")
        let targetDir = sandbox.appendingPathComponent("Applications")
        let destination = targetDir.appendingPathComponent("AppLocker.app")

        try createMockBundle(at: source, marker: "safe-payload")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let command = AppDirectoryPolicy.privilegedShellCommand(
            from: source,
            to: destination,
            stagingName: ".AppLocker.app.staging.test"
        )
        let exitCode = try runShell(command)

        #expect(exitCode == 0)
        #expect(!FileManager.default.fileExists(atPath: markerFile.path))
        #expect(try readMarker(in: destination) == "safe-payload")
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Privileged shell command keeps existing destination intact if copy fails")
    func privilegedShellCommandPreservesExistingOnCopyFailure() throws {
        let sandbox = try makeTempSandbox()
        defer { cleanupSandbox(sandbox) }

        let missingSource = sandbox.appendingPathComponent("DoesNotExist/AppLocker.app")
        let targetDir = sandbox.appendingPathComponent("Applications")
        let destination = targetDir.appendingPathComponent("AppLocker.app")
        try createMockBundle(at: destination, marker: "original")

        let command = AppDirectoryPolicy.privilegedShellCommand(
            from: missingSource,
            to: destination,
            stagingName: ".AppLocker.app.staging.fail"
        )
        let exitCode = try runShell(command)

        #expect(exitCode != 0)
        #expect(try readMarker(in: destination) == "original")
        let entries = try FileManager.default.contentsOfDirectory(atPath: targetDir.path)
        #expect(entries == ["AppLocker.app"])
    }

    @Test("Privileged shell command succeeds when source resides on a read-only directory")
    func privilegedShellCommandSucceedsWithReadOnlySource() throws {
        let sandbox = try makeTempSandbox()
        let readOnlyDir = sandbox.appendingPathComponent("ReadOnlyDMG")
        defer {
            _ = try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: readOnlyDir.path
            )
            cleanupSandbox(sandbox)
        }

        let source = readOnlyDir.appendingPathComponent("AppLocker.app")
        let targetDir = sandbox.appendingPathComponent("Applications")
        let destination = targetDir.appendingPathComponent("AppLocker.app")

        try createMockBundle(at: source, marker: "from-ro-dmg")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyDir.path)

        let command = AppDirectoryPolicy.privilegedShellCommand(
            from: source,
            to: destination,
            stagingName: ".AppLocker.app.staging.ro"
        )
        let exitCode = try runShell(command)

        #expect(exitCode == 0)
        #expect(try readMarker(in: destination) == "from-ro-dmg")
    }

    @Test("AppleScript string literal escapes backslashes and double quotes")
    func appleScriptEscapingHandlesSpecialCharacters() {
        let escaped = AppDirectoryPolicy.appleScriptStringLiteral(#"echo "a\b""#)
        #expect(escaped == #""echo \"a\\b\"""#)
    }

    // MARK: - Helpers

    private func makeTempSandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDirectoryPolicyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func cleanupSandbox(_ url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            Issue.record("Failed to clean up sandbox at \(url.path): \(error.localizedDescription)")
        }
    }

    private func createMockBundle(at bundleURL: URL, marker: String) throws {
        let contentsDir = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        let markerURL = contentsDir.appendingPathComponent("marker.txt")
        try marker.write(to: markerURL, atomically: true, encoding: .utf8)
    }

    private func readMarker(in bundleURL: URL) throws -> String {
        let markerURL = bundleURL.appendingPathComponent("Contents/marker.txt")
        return try String(contentsOf: markerURL, encoding: .utf8)
    }

    private func runShell(_ command: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
