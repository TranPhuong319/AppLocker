//
//  PresentationStateTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 19/11/26.
//

import AppKit
import Foundation
import OSLog
import Testing

enum AlertResult { case button(index: Int, title: String), cancelled }

@MainActor
enum AlertShow {
    static var stubbedResult: AlertResult = .cancelled

    @discardableResult
    static func show(
        title: String, message: String, style: NSAlert.Style,
        buttons: [String], cancelIndex: Int? = nil, defaultIndex: Int? = nil
    ) -> AlertResult {
        stubbedResult
    }
}

@MainActor
private struct IsolatedStateEnv {
    let tempDir: URL
    let defaultsSuiteName: String
    let userDefaults: UserDefaults
    let configStore: ConfigStore
    let manager: LockES

    func makeAppBundle(name: String, bundleID: String) throws -> URL {
        let appURL = tempDir.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": bundleID, "CFBundleExecutable": name, "CFBundleName": name
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        let execURL = macOSURL.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: execURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execURL.path)
        return appURL
    }

    func cleanup() {
        userDefaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDir)
    }

    static func make() throws -> IsolatedStateEnv {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLockerPresentationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let suiteName = "com.TranPhuong319.AppLocker.PresentationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = ConfigStore(baseDirectoryURL: tempDir, userDefaults: defaults, uid: 501)
        return IsolatedStateEnv(
            tempDir: tempDir, defaultsSuiteName: suiteName, userDefaults: defaults,
            configStore: store, manager: LockES(configStore: store)
        )
    }
}

@Suite("Presentation & User State Tests")
@MainActor
struct PresentationStateTests {

    private func makeApp(
        _ name: String, bundleID: String, path: String,
        source: AppSource = .user, originalName: String? = nil
    ) -> InstalledApp {
        InstalledApp(name: name, bundleID: bundleID, path: path, source: source, originalName: originalName ?? name)
    }

    // MARK: - FuzzySearch

    @Test("FuzzySearch ranks exact name > name substring > originalName > bundleID > path")
    func fuzzySearchRanksByPriorityAndSupportsMultiToken() {
        let apps = [
            makeApp("Alpha Tool", bundleID: "com.ex.alpha", path: "/Applications/NotesFolder/Alpha.app"),
            makeApp("Beta Utility", bundleID: "com.ex.notes.helper", path: "/Applications/Beta.app"),
            makeApp(
                "Ghi chú", bundleID: "com.apple.Notes",
                path: "/System/Applications/Notes.app", source: .system, originalName: "Notes"
            ),
            makeApp("Notes Pro", bundleID: "com.ex.pro", path: "/Applications/NotesPro.app"),
            makeApp("Notes", bundleID: "com.ex.exact", path: "/Applications/ExactNotes.app", originalName: "Exact")
        ]

        #expect(apps.filter(matching: "   ").map(\.name) == apps.map(\.name))

        let ranked = apps.filter(matching: "notes")
        #expect(ranked.map(\.name) == ["Notes", "Notes Pro", "Ghi chú", "Beta Utility", "Alpha Tool"])
        #expect(apps.filter(matching: "ghi apple").map(\.name) == ["Ghi chú"])
        #expect(apps.filter(matching: "notes nonexistent").isEmpty)
    }

    // MARK: - AppState List Refresh & Search

    @Test("AppState refreshAppLists partitions locked, user unlockable, and system unlockable apps")
    func appStateRefreshPartitionsAndSortsApps() throws {
        let env = try IsolatedStateEnv.make()
        defer { env.cleanup() }

        let safariURL = try env.makeAppBundle(name: "Safari", bundleID: "com.apple.Safari")
        let notesURL = try env.makeAppBundle(name: "Notes", bundleID: "com.apple.Notes")
        let slackURL = try env.makeAppBundle(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")

        env.manager.lockedApps[safariURL.path] = LockedAppConfig(
            bundleID: "com.apple.Safari", path: safariURL.path, execFile: "Safari", name: "Safari"
        )

        let installed = [
            makeApp("Slack", bundleID: "com.tinyspeck.slackmacgap", path: slackURL.path, source: .user),
            makeApp("Safari", bundleID: "com.apple.Safari", path: safariURL.path, source: .system),
            makeApp("Notes", bundleID: "com.apple.Notes", path: notesURL.path, source: .system)
        ]

        let state = AppState(manager: env.manager, isMock: true, installedAppsProvider: { installed })
        state.refreshAppLists()

        #expect(state.lockedAppObjects.map(\.name) == ["Safari"])
        #expect(state.unlockableApps.map(\.name) == ["Notes", "Slack"])
        #expect(state.userUnlockableApps.map(\.name) == ["Slack"])
        #expect(state.systemUnlockableApps.map(\.name) == ["Notes"])
    }

    @Test("AppState filters locked apps synchronously and debounces unlockable search")
    func appStateSearchFilteringAndDebounce() async throws {
        let env = try IsolatedStateEnv.make()
        defer { env.cleanup() }

        let state = AppState(manager: env.manager, isMock: true, installedAppsProvider: { [] })
        state.lockedAppObjects = [
            makeApp("Xcode", bundleID: "com.apple.dt.Xcode", path: "/Applications/Xcode.app"),
            makeApp("Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app")
        ]
        state.unlockableApps = [
            makeApp("Music", bundleID: "com.apple.Music", path: "/System/Applications/Music.app", source: .system),
            makeApp("Mail", bundleID: "com.apple.mail", path: "/System/Applications/Mail.app", source: .system)
        ]

        state.searchTextLockApps = "xcode"
        #expect(state.filteredLockedApps.map(\.name) == ["Xcode"])

        state.searchTextUnlockableApps = "mail"
        state.searchTextUnlockableApps = "music"
        #expect(state.filteredUnlockableApps.isEmpty)

        try await Task.sleep(for: .milliseconds(260))
        #expect(state.filteredUnlockableApps.map(\.name) == ["Music"])
    }

    // MARK: - AppState Sheets, TouchBar & Lock Flow

    @Test("AppState activeTouchBar priority and sheet dismissal helpers")
    func appStateTouchBarPriorityAndSheets() throws {
        let env = try IsolatedStateEnv.make()
        defer { env.cleanup() }

        let state = AppState(manager: env.manager, isMock: true, installedAppsProvider: { [] })
        #expect(state.activeTouchBar == .mainWindow)

        state.openMissingApps()
        #expect(state.activeTouchBar == .missingAppsPopup)
        state.showDeleteQueueSheet()
        #expect(state.activeTouchBar == .deleteQueuePopup)
        state.openAddApp()
        #expect(state.activeTouchBar == .addAppPopup)

        state.selectedToLock = ["/Applications/A.app"]
        state.searchTextLockApps = "Safari"
        state.searchTextUnlockableApps = "Music"
        state.dismissAddAppSheet()
        #expect(state.showingAddApp == false)
        #expect(state.selectedToLock.isEmpty)
        #expect(state.searchTextLockApps == "Safari")
        #expect(state.searchTextUnlockableApps.isEmpty)
        #expect(state.activeTouchBar == .deleteQueuePopup)

        state.deleteQueue = ["/Applications/B.app"]
        state.clearDeleteQueue()
        #expect(state.showingDeleteQueue == false)
        #expect(state.deleteQueue.isEmpty)
        #expect(state.activeTouchBar == .missingAppsPopup)

        state.closeMissingApps()
        #expect(state.activeTouchBar == .mainWindow)
    }

    @Test("AppState toggleLockPopup locks and unlocks apps, clears queues, and resets popup state")
    func appStateToggleLockPopupFlow() async throws {
        let env = try IsolatedStateEnv.make()
        defer { env.cleanup() }

        let appURL = try env.makeAppBundle(name: "DemoApp", bundleID: "com.example.demo")
        let installed = [makeApp("DemoApp", bundleID: "com.example.demo", path: appURL.path)]

        let state = AppState(manager: env.manager, isMock: true, installedAppsProvider: { installed })
        state.showingAddApp = true
        state.selectedToLock = [appURL.path]

        state.lockSelectedApps()
        #expect(state.showingAddApp == false)
        #expect(state.showingLockingPopup == true)
        #expect(!state.lockingMessage.isEmpty)

        for _ in 0..<200 where state.showingLockingPopup { try await Task.sleep(for: .milliseconds(10)) }

        #expect(state.showingLockingPopup == false)
        #expect(state.selectedToLock.isEmpty)
        #expect(env.manager.lockedApps[appURL.path]?.bundleID == "com.example.demo")
        #expect(state.lockedAppObjects.map(\.path) == [appURL.path])
        #expect(state.unlockableApps.isEmpty)

        state.showingDeleteQueue = true
        state.deleteQueue = [appURL.path]
        state.unlockQueuedApps()
        #expect(state.showingDeleteQueue == false)
        #expect(state.showingLockingPopup == true)

        for _ in 0..<200 where state.showingLockingPopup { try await Task.sleep(for: .milliseconds(10)) }

        #expect(state.showingLockingPopup == false)
        #expect(state.deleteQueue.isEmpty)
        #expect(env.manager.lockedApps.isEmpty)
        #expect(state.lockedAppObjects.isEmpty)
        #expect(state.unlockableApps.map(\.path) == [appURL.path])
    }

    // MARK: - Missing Apps, Auto-Unhide & Rename Migration

    @Test("AppState missing app grace period confirms after 5 seconds and clears when restored")
    func appStateMissingStatusGracePeriod() throws {
        let env = try IsolatedStateEnv.make()
        defer { env.cleanup() }
        let state = AppState(manager: env.manager, isMock: true, installedAppsProvider: { [] })
        let path = "/Applications/Vanished.app"
        let start = Date(timeIntervalSince1970: 1_000)

        #expect(state.checkMissingStatus(path: path, isHidden: false, now: start, fileExists: false) == (false, true))
        let mid = start.addingTimeInterval(3.0)
        #expect(state.checkMissingStatus(path: path, isHidden: false, now: mid, fileExists: false) == (false, true))
        let late = start.addingTimeInterval(5.1)
        #expect(state.checkMissingStatus(path: path, isHidden: false, now: late, fileExists: false) == (true, false))
        let hiddenNow = start.addingTimeInterval(10.0)
        #expect(
            state.checkMissingStatus(path: path, isHidden: true, now: hiddenNow, fileExists: false) == (false, false)
        )
        let restoredNow = start.addingTimeInterval(11.0)
        #expect(
            state.checkMissingStatus(path: path, isHidden: false, now: restoredNow, fileExists: true) == (false, false)
        )
        #expect(state.missingAppTimestamps[path] == nil)
    }

    @Test("AppState hides missing apps, auto-unhides restored apps, and migrates renamed apps")
    func appStateHideAutoUnhideAndRenameMigration() throws {
        let env = try IsolatedStateEnv.make()
        defer { env.cleanup() }

        let ghostPath = env.tempDir.appendingPathComponent("Ghost.app").path
        env.manager.lockedApps[ghostPath] = LockedAppConfig(
            bundleID: "com.example.ghost", path: ghostPath, execFile: "Ghost", name: "Ghost"
        )

        let state = AppState(manager: env.manager, isMock: true, installedAppsProvider: { [] })
        state.missingAppTimestamps[ghostPath] = Date().addingTimeInterval(-10)
        state.refreshAppLists()
        #expect(state.confirmedMissingApps.map(\.path) == [ghostPath])

        state.hideAllMissingApps()
        #expect(env.manager.lockedApps[ghostPath]?.isHidden == true)
        #expect(state.lockedAppObjects.isEmpty)

        _ = try env.makeAppBundle(name: "Ghost", bundleID: "com.example.ghost")
        state.refreshAppLists()
        #expect(env.manager.lockedApps[ghostPath]?.isHidden == false)
        #expect(state.lockedAppObjects.map(\.path) == [ghostPath])

        let movedURL = try env.makeAppBundle(name: "GhostRenamed", bundleID: "com.example.ghost")
        try FileManager.default.removeItem(atPath: ghostPath)
        let migrated = [makeApp("GhostRenamed", bundleID: "com.example.ghost", path: movedURL.path)]
        let migratingState = AppState(manager: env.manager, isMock: true, installedAppsProvider: { migrated })
        migratingState.refreshAppLists()
        #expect(env.manager.lockedApps[ghostPath] == nil)
        #expect(env.manager.lockedApps[movedURL.path]?.bundleID == "com.example.ghost")
        #expect(migratingState.lockedAppObjects.map(\.path) == [movedURL.path])
    }

    // MARK: - App Picker Delegate Validation

    @Test("AppState panel(shouldEnable:) blocks self, locked apps, and sensitive /System paths")
    func appStateOpenPanelFilterRules() throws {
        let env = try IsolatedStateEnv.make()
        defer { env.cleanup() }

        let lockedPath = "/Applications/AlreadyLocked.app"
        env.manager.lockedApps[lockedPath] = LockedAppConfig(
            bundleID: "com.example.locked", path: lockedPath, execFile: "AlreadyLocked", name: "AlreadyLocked"
        )

        let state = AppState(manager: env.manager, isMock: true, installedAppsProvider: { [] })
        let panel = NSObject()

        let selfURL = URL(fileURLWithPath: state.selfBundlePath, isDirectory: false)
        #expect(state.panel(panel, shouldEnable: selfURL) == false)
        #expect(state.panel(panel, shouldEnable: URL(fileURLWithPath: lockedPath)) == false)
        let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        #expect(state.panel(panel, shouldEnable: finderURL) == false)
        #expect(state.panel(panel, shouldEnable: URL(fileURLWithPath: "/System/Library/", isDirectory: true)) == false)
        #expect(state.panel(panel, shouldEnable: URL(fileURLWithPath: "/System/Applications/Calculator.app")) == true)
        #expect(state.panel(panel, shouldEnable: URL(fileURLWithPath: "/Applications/Firefox.app")) == true)
    }
}

@Suite("LockES Policy & LogSelection State Tests")
@MainActor
struct SupportingStateTests {

    @Test("LockES policy setters persist to isolated ConfigStore and respect protection disabled")
    func lockESPolicySettersAndPersistence() throws {
        let env = try IsolatedStateEnv.make()
        defer { env.cleanup() }

        let appURL = try env.makeAppBundle(name: "TargetApp", bundleID: "com.example.target")
        env.manager.toggleLock(for: [appURL.path])
        #expect(env.manager.isLocked(at: appURL.path) == true)

        env.manager.setProtectionDisabled(true)
        env.manager.setAllowIncomingCalls(false)
        env.manager.setAutoLockTimeoutMinutes(15)
        #expect(env.manager.isLocked(at: appURL.path) == false)

        let reloaded = env.configStore.load()
        #expect(reloaded.isDisabled == true)
        #expect(reloaded.allowIncomingCalls == false)
        #expect(reloaded.autoLockTimeoutMinutes == 15)
        #expect(reloaded.apps[appURL.path]?.bundleID == "com.example.target")

        env.manager.removeApps(for: [appURL.path])
        #expect(env.manager.lockedApps.isEmpty)
        #expect(env.configStore.load().apps.isEmpty)
    }

    // MARK: - LogSelectionManager

    @Test("LogSelectionManager tracks selection and formats selected entries on copy")
    func logSelectionManagerOperations() async {
        let manager = LogSelectionManager()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = GroupedLogEntry(
            entry: AppLogEntry(
                date: date, subsystem: "com.TranPhuong319.AppLocker",
                category: "App", level: .info, message: "First log"
            ),
            count: 1
        )
        let second = GroupedLogEntry(
            entry: AppLogEntry(
                date: date, subsystem: "com.TranPhuong319.AppLocker.ESExtension",
                category: "Security", level: .error, message: "Second log"
            ),
            count: 2
        )
        let entries = [first, second]
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        #expect(manager.hasSelection == false)
        manager.copySelected(entries: entries, dateFormatter: formatter)
        #expect(manager.isCopiedFeedback == false)

        manager.selectAll(entries: entries)
        #expect(manager.hasSelection == true)
        #expect(manager.selectedCount == 2)

        manager.selectedIDs = [second.id]
        manager.copySelected(entries: entries, dateFormatter: formatter)
        await Task.yield()
        #expect(manager.isCopiedFeedback == true)
        let copied = NSPasteboard.general.string(forType: .string) ?? ""
        #expect(copied.contains("[ESExt/Security] ERROR: Second log"))
        #expect(!copied.contains("First log"))

        manager.deselectAll()
        #expect(manager.hasSelection == false)
        #expect(manager.selectedCount == 0)
    }
}
