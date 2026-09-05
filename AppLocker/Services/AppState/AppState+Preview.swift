//
//  AppState+Preview.swift
//  AppLocker
//
//  Created by Doe Phương on 16/8/26.
//

import Foundation
import Observation
import SwiftUI

// MARK: - Mocking for Previews
@Observable
@MainActor
class MockLockManager: LockManagerProtocol {
    var lockedApps: [String: LockedAppConfig] = [:]
    var allApps: [InstalledApp] = []
    var isProtectionDisabled: Bool = false
    var allowIncomingCalls: Bool = true

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

    func setAllowIncomingCalls(_ allowed: Bool) {
        self.allowIncomingCalls = allowed
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
