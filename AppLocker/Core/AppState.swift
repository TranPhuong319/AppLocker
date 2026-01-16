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

class AppState: NSObject, ObservableObject, NSOpenSavePanelDelegate {
    static let shared = AppState()

    private let selfBundlePath = Bundle.main.bundleURL.path
    private let selfBundleName = Bundle.main.bundleURL.lastPathComponent
    private var query: NSMetadataQuery?
    @Published var manager: any LockManagerProtocol
    @Published var showingAddApp = false
    @Published var showingDeleteQueue = false
    @Published var selectedToLock: Set<String> = []
    @Published var pendingLocks: Set<String> = []
    @Published var deleteQueue: Set<String> = []
    @Published var isLocking = false
    @Published var lastUnlockableApps: [InstalledApp] = []
    @Published var showingMenu = false
    @Published var showingLockingPopup = false
    @Published var lockingMessage = ""
    @Published var searchTextLockApps = ""
    @Published var searchTextUnlockaleApps: String = ""

    @Published var filteredLockedApps: [InstalledApp] = []
    @Published var filteredUnlockableApps: [InstalledApp] = []

    @Published private(set) var lockedAppObjects: [InstalledApp] = []
    @Published private(set) var unlockableApps: [InstalledApp] = []

    override init() {
        let initialManager: any LockManagerProtocol
        switch modeLock {
        case .launcher:
            initialManager = LockLauncher()
        case .es:
            initialManager = LockES()
        case .none:
            Logfile.core.error("No mode selected during AppState init, defaulting to Launcher")
            initialManager = LockLauncher()
        }
        self.manager = initialManager

        super.init()

        setupSearchPipeline()
        setupSpotlightQuery()
        refreshAppLists()
    }

    private func setupSpotlightQuery() {
        query = NSMetadataQuery()
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate), name: .NSMetadataQueryDidFinishGathering,
            object: query)
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate), name: .NSMetadataQueryDidUpdate,
            object: query)

        query?.predicate = NSPredicate(
            format:
                "(kMDItemContentType == 'com.apple.application-bundle') || (kMDItemFSName ENDSWITH '.app')"
        )
        query?.searchScopes = ["/Applications", "/System/Applications"]
        query?.start()
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        let results = query?.results as? [NSMetadataItem] ?? []
        let selfPath = Bundle.main.bundleURL.path

        let apps: [InstalledApp] = results.compactMap { item in
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
            self.manager.allApps = apps
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
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.global())
            .map { [weak self] (text, apps) -> [InstalledApp] in
                guard let self = self else { return [] }
                return self.performFilter(text: text, apps: apps)
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$filteredUnlockableApps)
    }

    private func performFilter(text: String, apps: [InstalledApp]) -> [InstalledApp] {
        let query = text.alNormalized
        guard !query.isEmpty else { return apps }

        return apps.filter { app in
            fuzzyMatch(query: query, target: app.name)
                || fuzzyMatch(query: query, target: app.bundleID)
                || fuzzyMatch(query: query, target: app.path)
        }
    }

    private func refreshAppLists() {
        let locked: [InstalledApp] = manager.lockedApps.keys.compactMap { path -> InstalledApp? in
            guard manager.lockedApps[path] != nil else { return nil }

            let name = FileManager.default.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)

            let source: AppSource = path.hasPrefix("/System") ? .system : .user

            return InstalledApp(name: name, bundleID: "", path: path, source: source)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let allAppsFromManager: [InstalledApp] = manager.allApps

        let unlockable =
            allAppsFromManager
            .filter { (app: InstalledApp) -> Bool in
                return !manager.lockedApps.keys.contains(app.path)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        DispatchQueue.main.async {
            self.lockedAppObjects = locked
            self.unlockableApps = unlockable
        }
    }

    private func fuzzyMatch(query: String, target: String) -> Bool {
        let t = target.alNormalized
        if t.contains(query) { return true }
        var searchIndex = t.startIndex
        for char in query {
            guard
                let range = t.range(
                    of: String(char), options: String.CompareOptions.caseInsensitive,
                    range: searchIndex..<t.endIndex)
            else {
                return false
            }
            searchIndex = range.upperBound
        }
        return true
    }

    let setWidth = 450  // Chiều ngang
    let setHeight = 470  // chiều cao

    var appsToUnlock: [String] {
        Array(deleteQueue)
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

        DispatchQueue.global(qos: .userInitiated).async {
            self.manager.toggleLock(for: Array(apps))

            DispatchQueue.main.async {
                if locking {
                    self.selectedToLock.removeAll()
                    self.pendingLocks.removeAll()
                } else {
                    self.deleteQueue.removeAll()
                }

                self.manager.reloadAllApps()
                self.refreshAppLists()

                self.showingLockingPopup = false
            }
        }
    }

    func openAddApp() {
        let currentApps = self.unlockableApps
        if currentApps != lastUnlockableApps {
            lastUnlockableApps = currentApps
        }
        showingAddApp = true
    }

    func lockButton() {
        toggleLockPopup(for: selectedToLock, locking: true)
    }

    func closeAddPopup() {
        showingAddApp = false
        selectedToLock.removeAll()
        pendingLocks.removeAll()
        searchTextLockApps = ""
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

        if let window = window {
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

    func unlockApp() {
        toggleLockPopup(for: Set(appsToUnlock), locking: false)
    }

    func deleteAllFromWaitingList() {
        deleteQueue.removeAll()
        showingDeleteQueue = false
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
