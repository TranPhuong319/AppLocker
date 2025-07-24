//
//  AppUnlockState.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import Foundation

class AppUnlockState {
    static let shared = AppUnlockState()
    private var unlockedApps = Set<String>()

    func isUnlocked(_ bundleID: String) -> Bool {
        return unlockedApps.contains(bundleID)
    }

    func markUnlocked(_ bundleID: String) {
        unlockedApps.insert(bundleID)
    }

    func clear(_ bundleID: String) {
        unlockedApps.remove(bundleID)
    }

    func clearAll() {
        unlockedApps.removeAll()
    }
}
