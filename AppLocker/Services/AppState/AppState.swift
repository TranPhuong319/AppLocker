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
    @ObservationIgnored
    var appScanTask: Task<Void, Never>?
    @ObservationIgnored
    var cachedFileSystemApps: [InstalledApp] = []
    @ObservationIgnored
    var cachedSpotlightApps: [InstalledApp] = []
    var lastInstalledPathSet: Set<String> = []

    @ObservationIgnored
    private var searchUnlockableAppsTask: Task<Void, Never>?
    @ObservationIgnored
    var pendingMissingCheckTask: Task<Void, Never>?
    @ObservationIgnored
    var cdhashScanTask: Task<Void, Never>?
    @ObservationIgnored
    var cdhashPeriodicTask: Task<Void, Never>?
    @ObservationIgnored
    var directoryWatcherDebounceTask: Task<Void, Never>?
    @ObservationIgnored
    var directoryWatcherSource: DispatchSourceFileSystemObject?

    var manager: LockES
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
    var missingAppTimestamps: [String: Date] = [:]

    var isSearchPresented = false
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

    init(manager: LockES? = nil, isMock: Bool = false) {
        self.manager = manager ?? LockES()
        self.isMock = isMock

        super.init()

        if !isMock {
            self.manager.bootstrap { [weak self] in
                self?.refreshAppLists()
            }
            refreshInstalledApps()
            setupSpotlightQuery()
            startApplicationsWatcher()
            setupApplicationLifecycleObservers()
            setupPeriodicCDHashScan()
            refreshAppLists()
        }
    }

    deinit {
        cdhashScanTask?.cancel()
        cdhashPeriodicTask?.cancel()
        directoryWatcherDebounceTask?.cancel()
        pendingMissingCheckTask?.cancel()
        directoryWatcherSource?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupPeriodicCDHashScan() {
        cdhashPeriodicTask?.cancel()
        cdhashPeriodicTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1800))
                guard !Task.isCancelled, let self = self else { break }
                self.verifyAndHealLockedCDHashes()
            }
        }
    }

    private func setupApplicationLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshInstalledApps()
                self?.refreshAppLists()
            }
        }
    }

    var userUnlockableApps: [InstalledApp] {
        filteredUnlockableApps.filter { $0.source == .user }
    }

    var systemUnlockableApps: [InstalledApp] {
        filteredUnlockableApps.filter { $0.source == .system }
    }

    private func filterLockedApps() {
        filteredLockedApps = lockedAppObjects.filter(matching: searchTextLockApps)
    }

    private func debounceFilterUnlockableApps() {
        searchUnlockableAppsTask?.cancel()
        searchUnlockableAppsTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self = self else { return }
            self.filteredUnlockableApps = self.unlockableApps.filter(matching: self.searchTextUnlockableApps)
        }
    }
}
