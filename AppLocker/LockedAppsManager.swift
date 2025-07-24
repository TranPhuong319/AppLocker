//
//  LockedAppsManager.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import Foundation

class LockedAppsManager: ObservableObject {
    @Published var lockedApps: [String] = []

    private let configFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AppLocker/locked_apps.json")

    init() {
        load()
    }

    func load() {
        do {
            let data = try Data(contentsOf: configFile)
            lockedApps = try JSONDecoder().decode([String].self, from: data)
        } catch {
            lockedApps = []
        }
    }

    func save() {
        try? FileManager.default.createDirectory(at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try? JSONEncoder().encode(lockedApps)
        try? data?.write(to: configFile)
        // 🔒 Có thể chmod/chflags immutable để chống xoá file
        _ = shell("chflags uchg \(configFile.path)")
    }

    func toggleLock(for app: String) {
        if lockedApps.contains(app) {
            lockedApps.removeAll { $0 == app }
        } else {
            lockedApps.append(app)
        }
        save()
    }

    func isLocked(_ app: String) -> Bool {
        lockedApps.contains(app)
    }
}
