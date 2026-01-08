//
//  AppState.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//

import SwiftUI
import Combine

class AppState: NSObject, ObservableObject, NSOpenSavePanelDelegate {
    static let shared = AppState()
    @Published var manager: any LockManagerProtocol
    @Published var showingAddApp = false
    @Published var showingDeleteQueue = false
    @Published var selectedToLock: Set<String> = []
    @Published var pendingLocks: Set<String> = []
    @Published var deleteQueue: Set<String> = []
    @Published var isLocking = false
    @Published var lastUnlockableApps: [InstalledApp] = []
    @Published var showingMenu = false
    @Published var isDisabled = false
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
        refreshAppLists()
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
        let query = text.normalized
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

            let icon = NSWorkspace.shared.icon(forFile: path)
            let name = FileManager.default.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)

            let source: AppSource = path.hasPrefix("/System") ? .system : .user

            return InstalledApp(name: name, bundleID: "", icon: icon, path: path, source: source)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let allAppsFromManager: [InstalledApp] = manager.allApps

        let unlockable: [InstalledApp] = allAppsFromManager
            .filter { (app: InstalledApp) -> Bool in

                return !manager.lockedApps.keys.contains(app.path)
            }
            .map { app in
                if app.source == nil {
                    let src: AppSource = app.path.hasPrefix("/System") ? .system : .user
                    return InstalledApp(
                        name: app.name,
                        bundleID: app.bundleID,
                        icon: app.icon,
                        path: app.path,
                        source: src
                    )
                }
                return app
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        DispatchQueue.main.async {
            self.lockedAppObjects = locked
            self.unlockableApps = unlockable
        }
    }

    let setWidth = 450 // Chiều ngang
    let setHeight = 470 // chiều cao

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

        lockingMessage = locking
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

    func addOthersApp() {
        let panel = NSOpenPanel()
        panel.delegate = self
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]

        if panel.runModal() == .OK {
            let paths = Set(panel.urls.map { $0.path })
            if !paths.isEmpty {
                toggleLockPopup(for: paths, locking: true)
            }
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

        // Chặn chính app đang chạy
        if path == Bundle.main.bundleURL.path {
            return false
        }

        // Hoặc chặn theo bundle name (ít chính xác hơn path)
        if url.lastPathComponent == Bundle.main.bundleURL.lastPathComponent {
            return false
        }

        if manager.lockedApps.keys.contains(path) {
            return false
        }

        if path.hasPrefix("/System/") && !path.hasPrefix("/System/Applications/") {
            return false
        }

        return true
    }
}
