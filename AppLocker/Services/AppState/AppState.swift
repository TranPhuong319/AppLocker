//
//  AppState.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//

import Combine
import CoreServices
import Foundation
import SwiftUI

@MainActor
class AppState: NSObject, ObservableObject, NSOpenSavePanelDelegate {
    static let shared = AppState()

    let selfBundlePath = Bundle.main.bundleURL.path
    let selfBundleName = Bundle.main.bundleURL.lastPathComponent
    var metadataQuery: NSMetadataQuery?
    var spotlightWorkItem: DispatchWorkItem?
    var lastInstalledPathSet: Set<String> = []
    private var cancellables = Set<AnyCancellable>()
    @Published var manager: any LockManagerProtocol
    @Published var showingAddApp = false
    @Published var showingDeleteQueue = false
    @Published var selectedToLock: Set<String> = []
    @Published var deleteQueue: Set<String> = []
    @Published var isLocking = false
    @Published var showingLockingPopup = false
    @Published var lockingMessage = ""
    @Published var searchTextLockApps = ""
    @Published var searchTextUnlockaleApps: String = ""

    @Published var filteredLockedApps: [InstalledApp] = []
    @Published var filteredUnlockableApps: [InstalledApp] = []

    @Published var lockedAppObjects: [InstalledApp] = []
    @Published var unlockableApps: [InstalledApp] = []

    var isMock: Bool = false

    init(manager: (any LockManagerProtocol)? = nil) {
        if let manager = manager {
            self.manager = manager
            self.isMock = manager is MockLockManager
        } else {
            self.manager = LockES()
        }

        super.init()

        // After super.init, it's safe to use 'self' and access instance properties like 'cancellables'
        if let esManager = self.manager as? LockES {
            esManager.bootstrap()

            // AppState must observe changes because LockES loads asynchronously
            esManager.$lockedApps
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.refreshAppLists()
                }
                .store(in: &cancellables)
        }

        setupSearchPipeline()
        if !isMock {
            setupSpotlightQuery()
            refreshAppLists()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        metadataQuery?.stop()
    }

    private func setupSearchPipeline() {
        Publishers.CombineLatest($searchTextLockApps, $lockedAppObjects)
            .map { [weak self] (text, apps) -> [InstalledApp] in
                guard let self = self else { return [] }
                return self.performFilter(text: text, apps: apps)
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$filteredLockedApps)

        Publishers.CombineLatest($searchTextUnlockaleApps, $unlockableApps)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .map { [weak self] (text, apps) -> [InstalledApp] in
                guard let self = self else { return [] }
                return self.performFilter(text: text, apps: apps)
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$filteredUnlockableApps)
    }

    private func performFilter(text: String, apps: [InstalledApp]) -> [InstalledApp] {
        let query = text.normalized
        guard !query.isEmpty else { return apps }

        return apps.filter { app in
            fuzzyMatch(query: query, target: app.name)
                || fuzzyMatch(query: query, target: app.bundleID)
                || fuzzyMatch(query: query, target: app.path)
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

        DispatchQueue.global(qos: .utility).async {
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

    @Published var activeTouchBar: TouchBarType = .mainWindow

    enum TouchBarType {
        case mainWindow
        case addAppPopup
        case deleteQueuePopup
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
            try? await Task.sleep(nanoseconds: 150_000_000)

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

    @objc func lockButton() {
        toggleLockPopup(for: selectedToLock, locking: true)
    }

    @objc func closeAddPopup() {
        showingAddApp = false
        selectedToLock.removeAll()
        searchTextLockApps = ""
    }

    @objc func addAnotherApp() {
        addOthersApp(over: NSApp.keyWindow)
    }

    @objc func unlockApp() {
        toggleLockPopup(for: deleteQueue, locking: false)
    }

    @objc func deleteAllFromWaitingList() {
        deleteQueue.removeAll()
        showingDeleteQueue = false
    }

    @objc func showDeleteQueuePopup() {
        showingDeleteQueue = true
    }
}
