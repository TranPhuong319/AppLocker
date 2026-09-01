//
//  AppState.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//

import CoreServices
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
    var selectedToLock: Set<String> = []
    var deleteQueue: Set<String> = []
    var isLocking = false
    var showingLockingPopup = false
    var lockingMessage = ""

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

    func refreshAppLists() {
        let allApps = manager.allApps
        let lockedPathSet = Set(manager.lockedApps.keys)

        let lockedAppsList: [InstalledApp] = manager.lockedApps.keys.compactMap { path -> InstalledApp? in
            guard let config = manager.lockedApps[path] else { return nil }

            // 1. Ưu tiên lấy tên từ Spotlight (dữ liệu allApps) thông qua path hoặc bundleID
            var name = allApps.first(where: {
                $0.path == path || (!config.bundleID.isEmpty && $0.bundleID == config.bundleID)
            })?.name

            // 2. Dự phòng: Lấy từ FileManager display name nếu Spotlight chưa có/không thấy
            if name == nil {
                let displayName = FileManager.default.displayName(atPath: path)
                name = displayName.replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
            }

            // 3. Fallback cuối cùng: dùng tên trong config hoặc tên file
            let finalName = name ?? config.name ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let source: AppSource = path.hasPrefix("/System") ? .system : .user

            return InstalledApp(name: finalName, bundleID: config.bundleID, path: path, source: source)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let unlockable = allApps
            .filter { !lockedPathSet.contains($0.path) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        self.lockedAppObjects = lockedAppsList
        self.unlockableApps = unlockable
        self.filteredLockedApps = self.performFilter(text: self.searchTextLockApps, apps: lockedAppsList)
        self.filteredUnlockableApps = self.performFilter(text: self.searchTextUnlockableApps, apps: unlockable)

        Task(priority: .low) {
            for app in unlockable.prefix(60) {
                _ = AppIconProvider.shared.icon(forPath: app.path, size: 32)
            }
        }
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
