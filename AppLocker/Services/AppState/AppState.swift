//
//  AppState.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//

import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
class AppState: NSObject, NSOpenSavePanelDelegate {
    static let shared = AppState()

    let selfBundlePath = Bundle.main.bundleURL.path
    let selfBundleName = Bundle.main.bundleURL.lastPathComponent
    var metadataQuery: NSMetadataQuery?
    @ObservationIgnored
    var spotlightTask: Task<Void, Never>?
    var lastInstalledPathSet: Set<String> = []

    @ObservationIgnored
    private var searchUnlockableAppsTask: Task<Void, Never>?

    var manager: any LockManagerProtocol
    var showingAddApp = false
    var showingDeleteQueue = false
    var showingMissingAppsSheet = false
    var selectedToLock: Set<String> = []
    var deleteQueue: Set<String> = []
    var confirmedMissingApps: [InstalledApp] = []
    var isLocking = false
    var showingLockingPopup = false
    var lockingMessage = ""

    @ObservationIgnored
    fileprivate var missingAppTimestamps: [String: Date] = [:]

    var searchTextLockApps = "" {
        didSet {
            filterLockedApps()
        }
    }

    var searchTextUnlockableApps: String = "" {
        didSet {
            debounceFilterUnlockableApps()
        }
    }

    var filteredLockedApps: [InstalledApp] = []
    var filteredUnlockableApps: [InstalledApp] = []

    var lockedAppObjects: [InstalledApp] = []
    var unlockableApps: [InstalledApp] = []

    var isMock: Bool = false
    var activeTouchBar: TouchBarType = .mainWindow

    enum TouchBarType {
        case mainWindow
        case addAppPopup
        case deleteQueuePopup
        case missingAppsPopup
    }

    init(manager: (any LockManagerProtocol)? = nil) {
        if let manager = manager {
            self.manager = manager
            self.isMock = manager is MockLockManager
        } else {
            self.manager = LockES()
        }

        super.init()

        if let esManager = self.manager as? LockES {
            esManager.bootstrap { [weak self] in
                self?.refreshAppLists()
            }
        }

        if !isMock {
            setupSpotlightQuery()
            refreshAppLists()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func filterLockedApps() {
        filteredLockedApps = performFilter(text: searchTextLockApps, apps: lockedAppObjects)
    }

    private func debounceFilterUnlockableApps() {
        searchUnlockableAppsTask?.cancel()
        searchUnlockableAppsTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self = self else { return }
            self.filteredUnlockableApps = self.performFilter(
                text: self.searchTextUnlockableApps,
                apps: self.unlockableApps
            )
        }
    }

    private func performFilter(text: String, apps: [InstalledApp]) -> [InstalledApp] {
        let query = text.normalized
        guard !query.isEmpty else { return apps }
        let tokens = query.split(separator: " ")
        guard !tokens.isEmpty else { return apps }

        return apps.filter { app in
            fuzzyMatch(tokens, in: app.name)
                || fuzzyMatch(tokens, in: app.bundleID)
                || fuzzyMatch(tokens, in: app.path)
        }
    }

    private func resolveLockedApp(
        path: String,
        config: LockedAppConfig,
        allApps: [InstalledApp]
    ) -> InstalledApp {
        var name = allApps.first(where: {
            $0.path == path || (!config.bundleID.isEmpty && $0.bundleID == config.bundleID)
        })?.name

        if name == nil {
            let displayName = FileManager.default.displayName(atPath: path)
            name = displayName.replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
        }

        let finalName = name ?? config.name ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let source: AppSource = path.hasPrefix("/System") ? .system : .user
        return InstalledApp(name: finalName, bundleID: config.bundleID, path: path, source: source)
    }

    func refreshAppLists() {
        let allApps = manager.allApps
        let lockedPathSet = Set(manager.lockedApps.keys)
        var missingAppsList: [InstalledApp] = []
        var appsToUnhide: [String] = []
        let now = Date()
        var hasPendingCheck = false

        let lockedAppsList: [InstalledApp] = manager.lockedApps.keys.compactMap { path -> InstalledApp? in
            guard let config = manager.lockedApps[path] else { return nil }
            let app = self.resolveLockedApp(path: path, config: config, allApps: allApps)
            let fileExists = FileManager.default.fileExists(atPath: path)
            var isHidden = config.isHidden == true

            if isHidden && fileExists {
                appsToUnhide.append(path)
                isHidden = false
                AppIconProvider.shared.invalidateIcon(forPath: path)
            }

            let (isConfirmed, isPending) = self.checkMissingStatus(
                path: path,
                isHidden: isHidden,
                now: now,
                fileExists: fileExists
            )
            if isConfirmed { missingAppsList.append(app) }
            if isPending { hasPendingCheck = true }

            guard !isHidden else { return nil }
            return app
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if !appsToUnhide.isEmpty { manager.unhideApps(for: appsToUnhide) }
        if hasPendingCheck { schedulePendingMissingCheck() }

        let unlockable = allApps
            .filter { !lockedPathSet.contains($0.path) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        self.confirmedMissingApps = missingAppsList
        self.lockedAppObjects = lockedAppsList
        self.unlockableApps = unlockable
        self.filteredLockedApps = self.performFilter(text: self.searchTextLockApps, apps: lockedAppsList)
        self.filteredUnlockableApps = self.performFilter(text: self.searchTextUnlockableApps, apps: unlockable)

        prefetchUnlockableIcons(apps: unlockable)
    }

    var userUnlockableApps: [InstalledApp] {
        filteredUnlockableApps.filter { $0.source == .user }
    }

    var systemUnlockableApps: [InstalledApp] {
        filteredUnlockableApps.filter { $0.source == .system }
    }

    func toggleLockPopup(for apps: Set<String>, locking: Bool) {
        if locking {
            showingAddApp = false
        } else {
            showingDeleteQueue = false
        }

        lockingMessage =
            locking
            ? String(localized: "Locking \(apps.count) apps...")
            : String(localized: "Unlocking \(apps.count) apps...")
        showingLockingPopup = true

        let appsArray = Array(apps)

        Task {
            // Cho SwiftUI 1 nhịp (0.15s) để hiển thị mượt mà sheet LockingPopupSheet
            try? await Task.sleep(for: .milliseconds(150))

            self.manager.toggleLock(for: appsArray)

            if locking {
                self.selectedToLock.removeAll()
            } else {
                self.deleteQueue.removeAll()
            }

            self.refreshAppLists()

            self.showingLockingPopup = false
        }
    }

    @objc func openAddApp() {
        showingAddApp = true
    }

    @objc func lockSelectedApps() {
        toggleLockPopup(for: selectedToLock, locking: true)
    }

    @objc func dismissAddAppSheet() {
        showingAddApp = false
        selectedToLock.removeAll()
        searchTextLockApps = ""
    }

    @objc func chooseCustomApp() {
        addOtherApps(over: NSApp.keyWindow)
    }

    @objc func unlockQueuedApps() {
        toggleLockPopup(for: deleteQueue, locking: false)
    }

    @objc func clearDeleteQueue() {
        deleteQueue.removeAll()
        showingDeleteQueue = false
    }

    @objc func showDeleteQueueSheet() {
        showingDeleteQueue = true
    }
}

// MARK: - Missing Apps Handling
extension AppState {
    fileprivate func checkMissingStatus(
        path: String,
        isHidden: Bool,
        now: Date,
        fileExists: Bool
    ) -> (isConfirmed: Bool, isPending: Bool) {
        guard !fileExists else {
            if missingAppTimestamps.removeValue(forKey: path) != nil {
                AppIconProvider.shared.invalidateIcon(forPath: path)
            }
            return (false, false)
        }
        guard !isHidden else { return (false, false) }
        let firstDetected = missingAppTimestamps[path] ?? now
        missingAppTimestamps[path] = firstDetected
        let isConfirmed = now.timeIntervalSince(firstDetected) >= 3.0
        return (isConfirmed, !isConfirmed)
    }

    fileprivate func schedulePendingMissingCheck() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.0))
            guard !Task.isCancelled, let self = self else { return }
            self.refreshAppLists()
        }
    }

    fileprivate func prefetchUnlockableIcons(apps: [InstalledApp]) {
        Task(priority: .low) {
            for app in apps.prefix(60) {
                _ = AppIconProvider.shared.icon(forPath: app.path, size: 32)
            }
        }
    }

    func hideMissingApps(paths: [String]) {
        AuthenticationManager.authenticate(
            reason: String(localized: "authenticate to hide missing applications")
        ) { [weak self] success, _ in
            guard success, let self = self else { return }
            self.manager.hideApps(for: paths)
            for path in paths {
                self.missingAppTimestamps.removeValue(forKey: path)
            }
            self.refreshAppLists()
            self.showingMissingAppsSheet = false
        }
    }

    func deleteMissingApps(paths: [String]) {
        AuthenticationManager.authenticate(
            reason: String(localized: "authenticate to remove missing applications")
        ) { [weak self] success, _ in
            guard success, let self = self else { return }
            self.manager.removeApps(for: paths)
            for path in paths {
                self.missingAppTimestamps.removeValue(forKey: path)
            }
            self.refreshAppLists()
            self.showingMissingAppsSheet = false
        }
    }

    @objc func openMissingApps() {
        showingMissingAppsSheet = true
    }

    @objc func closeMissingApps() {
        showingMissingAppsSheet = false
    }
}
