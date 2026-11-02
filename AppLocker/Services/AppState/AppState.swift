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

    @ObservationIgnored
    private var searchUnlockableAppsTask: Task<Void, Never>?
    @ObservationIgnored
    var pendingMissingCheckTask: Task<Void, Never>?

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
        self.manager = manager ?? LockES.shared
        self.isMock = isMock

        super.init()

        if !isMock {
            setupNotificationObservers()
            refreshAppLists()
        }
    }

    deinit {
        pendingMissingCheckTask?.cancel()
        searchUnlockableAppsTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .installedAppsDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAppLists()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .lockedAppsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAppLists()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                AppScannerService.shared.refreshInstalledApps()
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
