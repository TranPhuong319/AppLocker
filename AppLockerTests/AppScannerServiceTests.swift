//
//  AppScannerServiceTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 7/11/26.
//

import CoreServices
import Foundation
import Testing

private final class MockMetadataItem: NSMetadataItem, @unchecked Sendable {
    let mockAttributes: [String: Any]

    init(mockAttributes: [String: Any]) {
        self.mockAttributes = mockAttributes
        super.init()
    }

    override func value(forAttribute key: String) -> Any? {
        mockAttributes[key]
    }
}

@Suite("AppScannerService Directory Scan, Spotlight Refinement & State Tests")
struct AppScannerServiceTests {

    // MARK: - Directory Scanning Tests

    @Test("scanApplicationsDirectories scans .app bundles and ignores non-app or hidden files")
    func scanApplicationsDirectoriesWithMockFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppScannerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create mock .app bundles and extraneous files
        let app1 = tempDir.appendingPathComponent("Alpha.app")
        let app2 = tempDir.appendingPathComponent("Beta.app")
        let hiddenApp = tempDir.appendingPathComponent(".Hidden.app")
        let textFile = tempDir.appendingPathComponent("Notes.txt")

        try FileManager.default.createDirectory(at: app1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hiddenApp, withIntermediateDirectories: true)
        try "test".write(to: textFile, atomically: true, encoding: .utf8)

        let scanned = AppScannerService.scanApplicationsDirectories(
            directories: [tempDir.path],
            excluding: app1.path
        )

        #expect(scanned.count == 1)
        #expect(scanned.first?.path == app2.path)
        #expect(scanned.first?.source == .user)
        #expect(scanned.first?.originalName == "Beta")
    }

    @Test("scanApplicationsDirectories ignores deep nested apps and avoids DoS/recursion")
    func scanApplicationsDirectoriesDeepNestingIgnored() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppScannerDeepTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Root app
        let rootApp = tempDir.appendingPathComponent("RootApp.app")
        try FileManager.default.createDirectory(at: rootApp, withIntermediateDirectories: true)

        // Create 30 levels of nested directories
        var nestedDir = tempDir
        for level in 1...30 {
            nestedDir = nestedDir.appendingPathComponent("level_\(level)")
        }
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        // Deep hidden app
        let hiddenDeepApp = nestedDir.appendingPathComponent("HiddenDeep.app")
        try FileManager.default.createDirectory(at: hiddenDeepApp, withIntermediateDirectories: true)

        let scanned = AppScannerService.scanApplicationsDirectories(
            directories: [tempDir.path]
        )

        #expect(scanned.count == 1)
        #expect(scanned.first?.originalName == "RootApp")
        #expect(!scanned.contains { $0.originalName == "HiddenDeep" })
    }

    @Test("scanApplicationsDirectories discovers system applications and sorts alphabetically")
    func scanApplicationsDirectoriesSystemApps() {
        let scanned = AppScannerService.scanApplicationsDirectories(
            directories: ["/System/Applications"]
        )

        #expect(!scanned.isEmpty)
        for app in scanned {
            #expect(app.source == .system)
            #expect(app.path.hasPrefix("/System/Applications"))
        }

        // Verify alphabetical sorting
        for idx in 0..<(scanned.count - 1) {
            let comparison = scanned[idx].name.localizedStandardCompare(scanned[idx + 1].name)
            #expect(comparison != .orderedDescending)
        }
    }

    // MARK: - Spotlight Metadata Parsing Tests

    @Test("parseSpotlightResults parses metadata items and excludes invalid paths")
    @MainActor
    func parseSpotlightResultsValidation() {
        let service = AppScannerService()

        let validItem = MockMetadataItem(mockAttributes: [
            "kMDItemPath": "/Applications/ValidApp.app",
            "kMDItemDisplayName": "Valid App.app",
            "kMDItemBundleIdentifier": "com.test.valid"
        ])

        let nestedItem = MockMetadataItem(mockAttributes: [
            "kMDItemPath": "/Applications/ValidApp.app/Contents/Frameworks/Helper.app",
            "kMDItemDisplayName": "Helper",
            "kMDItemBundleIdentifier": "com.test.helper"
        ])

        let outsideItem = MockMetadataItem(mockAttributes: [
            "kMDItemPath": "/Users/test/Downloads/Untrusted.app",
            "kMDItemDisplayName": "Untrusted",
            "kMDItemBundleIdentifier": "com.test.untrusted"
        ])

        let selfItem = MockMetadataItem(mockAttributes: [
            "kMDItemPath": service.selfBundlePath,
            "kMDItemDisplayName": "AppLocker",
            "kMDItemBundleIdentifier": "com.TranPhuong319.AppLocker"
        ])

        let results = service.parseSpotlightResults([validItem, nestedItem, outsideItem, selfItem])

        #expect(results.count == 1)
        #expect(results.first?.name == "Valid App")
        #expect(results.first?.bundleID == "com.test.valid")
        #expect(results.first?.path == "/Applications/ValidApp.app")
        #expect(results.first?.source == .user)
    }

    // MARK: - Spotlight Metadata Refinement Tests

    @Test("refineWithSpotlightMetadata updates display names and preserves sorting")
    @MainActor
    func refineWithSpotlightMetadataUpdates() {
        let service = AppScannerService()
        let initialApp1 = InstalledApp(
            name: "Calculator",
            bundleID: "com.apple.calc",
            path: "/System/Applications/Calculator.app",
            source: .system,
            originalName: "Calculator"
        )
        let initialApp2 = InstalledApp(
            name: "TextEdit",
            bundleID: "",
            path: "/Applications/TextEdit.app",
            source: .user,
            originalName: "TextEdit"
        )

        service.installedApps = [initialApp1, initialApp2]

        // Spotlight provides localized name for Calculator and bundleID for TextEdit
        let spotlightApps = [
            InstalledApp(
                name: "Máy tính",
                bundleID: "com.apple.calc",
                path: "/System/Applications/Calculator.app",
                source: .system,
                originalName: "Calculator"
            ),
            InstalledApp(
                name: "TextEdit",
                bundleID: "com.apple.TextEdit",
                path: "/Applications/TextEdit.app",
                source: .user,
                originalName: "TextEdit"
            ),
            InstalledApp(
                name: "App Store",
                bundleID: "com.apple.AppStore",
                path: "/System/Applications/App Store.app",
                source: .system,
                originalName: "App Store"
            )
        ]

        service.refineWithSpotlightMetadata(spotlightApps)

        #expect(service.installedApps.count == 3)
        let calc = service.installedApps.first { $0.path == "/System/Applications/Calculator.app" }
        #expect(calc?.name == "Máy tính")

        let textEdit = service.installedApps.first { $0.path == "/Applications/TextEdit.app" }
        #expect(textEdit?.bundleID == "com.apple.TextEdit")

        let appStore = service.installedApps.first { $0.path == "/System/Applications/App Store.app" }
        #expect(appStore != nil)
    }

    // MARK: - Publish Installed Apps & Notification Tests

    @Test("publishInstalledApps posts notification when apps change")
    @MainActor
    func publishInstalledAppsNotification() {
        let service = AppScannerService()
        final class ReceivedBox: @unchecked Sendable {
            var value = false
        }
        let box = ReceivedBox()

        let token = NotificationCenter.default.addObserver(
            forName: .installedAppsDidUpdate,
            object: nil,
            queue: .main
        ) { _ in
            box.value = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let sampleApp = InstalledApp(
            name: "TestApp",
            bundleID: "com.test.app",
            path: "/Applications/TestApp.app",
            source: .user,
            originalName: "TestApp"
        )

        service.publishInstalledApps([sampleApp])

        #expect(service.installedApps.count == 1)
        #expect(box.value == true)
    }
}
