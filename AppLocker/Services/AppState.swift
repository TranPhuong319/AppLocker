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

    private let selfBundlePath = Bundle.main.bundleURL.path
    private let selfBundleName = Bundle.main.bundleURL.lastPathComponent
    private var metadataQuery: NSMetadataQuery?
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

    @Published private(set) var lockedAppObjects: [InstalledApp] = []
    @Published private(set) var unlockableApps: [InstalledApp] = []

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

    private func setupSpotlightQuery() {
        let query = NSMetadataQuery()
        self.metadataQuery = query

        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate), name: .NSMetadataQueryDidFinishGathering,
            object: query)
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate), name: .NSMetadataQueryDidUpdate,
            object: query)

        query.predicate = NSPredicate(
            format:
                "(kMDItemContentType == 'com.apple.application-bundle') || (kMDItemFSName ENDSWITH '.app')"
        )
        metadataQuery?.searchScopes = ["/Applications", "/System/Applications"]
        metadataQuery?.start()
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        let results = metadataQuery?.results as? [NSMetadataItem] ?? []
        let selfPath = Bundle.main.bundleURL.path

        let installedAppsList: [InstalledApp] = results.compactMap { item in
            guard let path = item.value(forAttribute: "kMDItemPath") as? String,
                path != selfPath,
                !path.contains(".app/"),
                let rawName = item.value(forAttribute: "kMDItemDisplayName") as? String
            else { return nil }

            let name = rawName.replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)

            let bundleID =
                item.value(forAttribute: "kMDItemBundleIdentifier") as? String ?? ""
            let source: AppSource = path.hasPrefix("/System") ? .system : .user

            return InstalledApp(name: name, bundleID: bundleID, path: path, source: source)
        }

        DispatchQueue.main.async {
            self.manager.allApps = installedAppsList
            self.refreshAppLists()
        }
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

    private func refreshAppLists() {
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

        DispatchQueue.main.async {
            self.lockedAppObjects = lockedAppsList
            self.unlockableApps = unlockable
        }

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

    // Kích thước window/sheet đã chuyển sang WindowLayout.swift

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

    func addOthersApp(over window: NSWindow? = nil) {
        let panel = NSOpenPanel()
        panel.delegate = self
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.message = String(localized: "Select the application to lock")
        panel.prompt = String(localized: "Lock")

        if let window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK {
                    self.processSelectedPaths(panel.urls.map { $0.path })
                }
            }
        } else {
            if panel.runModal() == .OK {
                processSelectedPaths(panel.urls.map { $0.path })
            }
        }
    }

    private func processSelectedPaths(_ paths: [String]) {
        let pathsSet = Set(paths)
        if !pathsSet.isEmpty {
            toggleLockPopup(for: pathsSet, locking: true)
        }
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

    // MARK: - NSOpenSavePanelDelegate
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        let path = url.path

        // 1. Chặn chính app đang chạy (Dùng cache O(1))
        if path == selfBundlePath || url.lastPathComponent == selfBundleName {
            return false
        }

        // 2. Kiểm tra danh sách đã khóa (O(1) thay vì O(n))
        if manager.lockedApps[path] != nil {
            return false
        }

        // 3. Chặn các thư mục hệ thống nhạy cảm (Tối ưu hóa string prefix)
        if path.hasPrefix("/System/") {
            // Chỉ cho phép duyệt trong /System/Applications/
            if !path.hasPrefix("/System/Applications/") {
                return false
            }
        }

        return true
    }
}

// MARK: - Mocking for Previews
@MainActor
class MockLockManager: LockManagerProtocol, ObservableObject {
    @Published var lockedApps: [String: LockedAppConfig] = [:]
    @Published var allApps: [InstalledApp] = []
    @Published var isProtectionDisabled: Bool = false

    func toggleLock(for paths: [String]) {
        for path in paths {
            if lockedApps[path] != nil {
                lockedApps.removeValue(forKey: path)
            } else {
                lockedApps[path] = LockedAppConfig(
                    bundleID: "com.mock.app",
                    path: path,
                    sha256: "mock_sha256",
                    execFile: "MockApp",
                    name: "Mock App"
                )
            }
        }
    }

    func setProtectionDisabled(_ disabled: Bool) {
        self.isProtectionDisabled = disabled
    }

    func isLocked(path: String) -> Bool {
        lockedApps[path] != nil
    }
}

extension AppState {
    static func preview(locked: [InstalledApp] = [], deleteQueue: Set<String> = []) -> AppState {
        let mockManager = MockLockManager()
        mockManager.allApps = InstalledApp.allMocks

        var lockedConfigs: [String: LockedAppConfig] = [:]
        for app in locked {
            lockedConfigs[app.path] = .mock(for: app)
        }
        mockManager.lockedApps = lockedConfigs

        let state = AppState(manager: mockManager)
        state.deleteQueue = deleteQueue

        // Populate lists synchronously for instantaneous preview
        state.lockedAppObjects = locked.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        state.unlockableApps = InstalledApp.allMocks.filter { app in
            !locked.contains(where: { $0.path == app.path })
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Trigger search pipeline update
        state.filteredLockedApps = state.lockedAppObjects
        state.filteredUnlockableApps = state.unlockableApps

        return state
    }
}
