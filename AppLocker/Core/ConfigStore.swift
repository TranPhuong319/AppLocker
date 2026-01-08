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

    var configURL: URL {
        switch modeLock {
        case .launcher:
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            let dir = appSupport.appendingPathComponent("AppLocker", isDirectory: true)
            try? ensureDirectoryExists(dir)
            return dir.appendingPathComponent("config.plist")

        case .es:
            let dir = URL(
                fileURLWithPath: "/Users/Shared/AppLocker",
                isDirectory: true
            )
            try? ensureDirectoryExists(dir)
            return dir.appendingPathComponent("config.plist")

        case .none:
            fatalError()
        }
    }

    private func ensureDirectoryExists(_ dir: URL) throws {
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [
                    .posixPermissions: 0o755
                ]
            )
        }
    }

    private func shouldRequestES() -> Bool {
        return modeLock != AppMode.launcher
    }

    private func requestAccessIfNeeded(completion: @escaping (Bool) -> Void) {
        guard shouldRequestES() else {
            completion(true) // skip request nếu Launcher
            return
        }
        let pid = getpid()
        ESXPCClient.shared.allowConfigAccess(pid) { success in
            completion(success)
        }
    }

    func load() -> [String: LockedAppConfig] {
        var result: [String: LockedAppConfig] = [:]

        let group = DispatchGroup()
        group.enter()
        requestAccessIfNeeded { _ in
            group.leave()
        }
        group.wait()

        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL) else {
            return [:]
        }

        let decoder = PropertyListDecoder()

        switch modeLock {
        case .launcher:
            if let container = try? decoder.decode([String: [LockedAppConfig]].self, from: data),
               let arr = container["BlockedApps"] {
                for item in arr {
                    result[item.path] = item
                }
            } else if let arr = try? decoder.decode([LockedAppConfig].self, from: data) {
                for item in arr {
                    result[item.path] = item
                }
            }

        case .es:
            let uid = String(getuid())
            if let userMap = try? decoder.decode([String: [LockedAppConfig]].self, from: data),
               let apps = userMap[uid] {
                for app in apps {
                    result[app.path] = app
                }
            }

        case .none:
            return [:]
        }

        return result
    }

    func save(_ map: [String: LockedAppConfig]) {
        let group = DispatchGroup()
        group.enter()
        requestAccessIfNeeded { _ in
            group.leave()
        }
        group.wait()

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        do {
            switch modeLock {
            case .launcher:
                let arr = Array(map.values)
                let dict: [String: [LockedAppConfig]] = ["BlockedApps": arr]
                let data = try encoder.encode(dict)
                try data.write(to: configURL, options: .atomic)
                Logfile.core.info("ConfigStore.save launcher: wrote \(arr.count) apps")

            case .es:
                let uid = String(getuid())   // uid hiện tại
                let userDict: [String: [LockedAppConfig]] = [
                    uid: Array(map.values)
                ]
                let data = try encoder.encode(userDict)
                try data.write(to: configURL, options: .atomic)
                Logfile.core.info("ConfigStore.save ES: wrote \(map.count) apps for uid \(uid)")

            case .none:
                return
            }
        } catch {
            Logfile.core.error("ConfigStore.save failed: \(error.localizedDescription)")
        }
    }

}
