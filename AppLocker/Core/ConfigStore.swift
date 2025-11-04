//
//  ConfigStore.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation

final class ConfigStore {
    static let shared = ConfigStore()
    private init() {}
    
    private var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AppLocker", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("config.plist")
    }

    private func shouldRequestES() -> Bool {
        let modeLock = UserDefaults.standard.string(forKey: "selectedMode") ?? "ES"
        return modeLock != "Launcher"
    }
    
    private func requestAccessIfNeeded(completion: @escaping (Bool) -> Void) {
        guard shouldRequestES() else {
            completion(true) // skip request nếu Launcher
            return
        }
        let pid = getpid()
        ESXPCClient.shared.allowConfigAccess(pid) { ok in
            completion(ok)
        }
    }

    func load() -> [String: LockedAppConfig] {
        var result: [String: LockedAppConfig] = [:]

        let group = DispatchGroup()
        group.enter()
        requestAccessIfNeeded { _ in
            group.leave()
        }
        group.wait() // chờ ES request nếu cần

        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL) else {
            return [:]
        }

        let decoder = PropertyListDecoder()
        if let container = try? decoder.decode([String: [LockedAppConfig]].self, from: data),
           let arr = container["BlockedApps"] {
            for item in arr { result[item.path] = item }
        } else if let arr = try? decoder.decode([LockedAppConfig].self, from: data) {
            for item in arr { result[item.path] = item }
        }
        return result
    }

    func save(_ map: [String: LockedAppConfig]) {
        let arr = Array(map.values)
        let dict: [String: [LockedAppConfig]] = ["BlockedApps": arr]

        let group = DispatchGroup()
        group.enter()
        requestAccessIfNeeded { _ in
            group.leave()
        }
        group.wait() // chờ ES request nếu cần

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        do {
            let data = try encoder.encode(dict)
            try data.write(to: self.configURL, options: .atomic)
            NSLog("✅ ConfigStore.save success: wrote \(arr.count) apps")
        } catch {
            NSLog("❌ ConfigStore.save failed: \(error.localizedDescription)")
        }
    }
}
