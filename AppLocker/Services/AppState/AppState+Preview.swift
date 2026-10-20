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
extension AppState {
    static func preview(locked: [InstalledApp] = [], deleteQueue: Set<String> = []) -> AppState {
        let mockManager = LockES()
        mockManager.allApps = InstalledApp.allMocks

        var lockedConfigs: [String: LockedAppConfig] = [:]
        for app in locked {
            lockedConfigs[app.path] = .mock(for: app)
        }
        mockManager.lockedApps = lockedConfigs

        let state = AppState(manager: mockManager, isMock: true)
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
