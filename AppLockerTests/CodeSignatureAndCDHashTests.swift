//
//  CodeSignatureAndCDHashTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 4/11/26.
//

import Darwin
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
