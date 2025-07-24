//
//  AppUnlockState.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import Foundation

class AppUnlockState {
    static let shared = AppUnlockState()
    private var unlockedApps = Set<String>()         // những bundleID đã xác thực thành công

    func isUnlocked(bundleID: String) -> Bool {
        unlockedApps.contains(bundleID)
    }

    func markUnlocked(bundleID: String) {
        unlockedApps.insert(bundleID)
    }
}
