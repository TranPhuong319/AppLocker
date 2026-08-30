//
//  ESManager+Config.swift
//  ESExtension
//
//  Created by Antigravity on 06/02/26.
//

import Foundation
import os

extension ESManager {
    static let baseConfigDirectory = "/Users/Shared/AppLocker"
    static let legacyConfigPath = "/Users/Shared/AppLocker/config.plist"

    /// Đọc cấu hình từ tất cả các file /Users/Shared/AppLocker/<UID>/config.plist và cập nhật vào bộ nhớ ngay lập tức
    func loadInitialConfigSync() {
        guard let (loadedCDHashes, loadedBundlePaths) = readConfigsFromDisk() else {
            return
        }

        // Atomic Swap
        self.stateLock.withLock {
            self.lockedCDHashes = loadedCDHashes
            self.lockedBundlePaths = loadedBundlePaths
        }

        let totalApps = loadedBundlePaths.values.reduce(0) { $0 + $1.count }
        Logfile.endpointSecurity.info(
            """
            [ESConfig] Loaded \(totalApps, privacy: .public) apps for \
            \(loadedCDHashes.count, privacy: .public) users from per-user configs.
            """
        )
    }

    private func readConfigsFromDisk() -> ([uid_t: Set<String>], [uid_t: Set<String>])? {
        let fileManager = FileManager.default
        let baseDir = ESManager.baseConfigDirectory
        guard fileManager.fileExists(atPath: baseDir) else {
            Logfile.endpointSecurity.debug(
                "[ESConfig] Base config directory not found at \(baseDir, privacy: .public). Skipping load."
            )
            return nil
        }

        var newCDHashes: [uid_t: Set<String>] = [:]
        var newBundlePaths: [uid_t: Set<String>] = [:]

        // 1. Quét các thư mục con tương ứng với từng UID
        if let subpaths = try? fileManager.contentsOfDirectory(atPath: baseDir) {
            let decoder = PropertyListDecoder()
            for item in subpaths {
                guard let uid = uid_t(item) else { continue }
                let userConfigPath = (baseDir as NSString).appendingPathComponent("\(item)/config.plist")
                guard fileManager.fileExists(atPath: userConfigPath),
                      let data = try? Data(contentsOf: URL(fileURLWithPath: userConfigPath), options: .mappedIfSafe),
                      let userConfig = try? decoder.decode(UserConfig.self, from: data) else {
                    continue
                }

                guard !userConfig.isDisabled else { continue }
                let (cdhashes, bundlePaths) = extractHashesAndPaths(from: userConfig.apps)
                newCDHashes[uid] = cdhashes
                newBundlePaths[uid] = bundlePaths
            }
        }

        // 2. Dự phòng: Nếu chưa có file con nào nhưng có file legacy config.plist
        if newCDHashes.isEmpty && fileManager.fileExists(atPath: ESManager.legacyConfigPath) {
            if let legacyData = try? Data(
                contentsOf: URL(fileURLWithPath: ESManager.legacyConfigPath),
                options: .mappedIfSafe
            ) {
                return parseLegacyConfigData(legacyData)
            }
        }

        return (newCDHashes, newBundlePaths)
    }

    private func extractHashesAndPaths(from apps: [LockedAppConfig]) -> (Set<String>, Set<String>) {
        var cdhashes = Set<String>()
        var bundlePaths = Set<String>()

        for app in apps {
            let path1 = app.path
            let path2 = (path1 as NSString).standardizingPath
            let realPath = URL(fileURLWithPath: path1).resolvingSymlinksInPath().path
            bundlePaths.insert(path1)
            bundlePaths.insert(path2)
            bundlePaths.insert(realPath)

            let resolvedCDHash = app.cdhash ?? extractCDHash(forPath: path1)
            if let hash = resolvedCDHash, !hash.isEmpty {
                cdhashes.insert(hash.lowercased())
            }
        }

        return (cdhashes, bundlePaths)
    }

    private func parseLegacyConfigData(_ data: Data) -> ([uid_t: Set<String>], [uid_t: Set<String>]) {
        let decoder = PropertyListDecoder()
        var newCDHashes: [uid_t: Set<String>] = [:]
        var newBundlePaths: [uid_t: Set<String>] = [:]

        if let rawConfig = try? decoder.decode([String: UserConfig].self, from: data) {
            for (uidString, userConfig) in rawConfig {
                guard let uid = uid_t(uidString), !userConfig.isDisabled else { continue }
                let (hashes, paths) = extractHashesAndPaths(from: userConfig.apps)
                newCDHashes[uid] = hashes
                newBundlePaths[uid] = paths
            }
        } else if let oldConfig = try? decoder.decode([String: [LockedAppConfig]].self, from: data) {
            for (uidString, apps) in oldConfig {
                guard let uid = uid_t(uidString) else { continue }
                let (hashes, paths) = extractHashesAndPaths(from: apps)
                newCDHashes[uid] = hashes
                newBundlePaths[uid] = paths
            }
        }

        return (newCDHashes, newBundlePaths)
    }

    /// Theo dõi thay đổi của thư mục chứa cấu hình để bắt được sự kiện Atomic Write (Rename/Delete/Create)
    func startConfigMonitoring() {
        let configDir = ESManager.baseConfigDirectory

        configMonitorSource?.cancel()
        configMonitorSource = nil

        let fileDescriptor = open(configDir, O_EVTONLY)

        guard fileDescriptor != -1 else {
            Logfile.endpointSecurity.error(
                "[ESConfig] Failed to open config directory for monitoring: \(configDir, privacy: .public)"
            )
            backgroundProcessingQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.startConfigMonitoring()
            }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write], // Directory write covers file create/delete/rename in folder
            queue: backgroundProcessingQueue
        )

        var debounceTimer: DispatchSourceTimer?

        source.setEventHandler { [weak self] in
            guard let self = self else { return }

            debounceTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.backgroundProcessingQueue)
            timer.schedule(deadline: .now() + 0.05) // Debounce 50ms for instant update
            timer.setEventHandler { [weak self] in
                Logfile.endpointSecurity.debug("[ESConfig] Directory change detected, reloading config...")
                self?.loadInitialConfigSync()
                timer.cancel()
            }
            timer.resume()
            debounceTimer = timer
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        self.configMonitorSource = source
        source.resume()
        Logfile.endpointSecurity.info("[ESConfig] Started directory monitoring for \(configDir, privacy: .public)")
    }

    // MARK: - Language Configuration

    // Force the extension process to use a specific language.
    @objc func updateLanguage(to code: String) {
        guard isCurrentConnectionAuthenticated() else {
            Logfile.endpointSecurity.error("[ESConfig] Unauthorized call to updateLanguage")
            return
        }
        stateLock.withLock {
            self.currentLanguage = code
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            Logfile.endpointSecurity.debug("[ESConfig] ES process language updated to: \(code, privacy: .public)")
        }
    }

    // Read the current language in a thread-safe way.
    func getCurrentLanguage() -> String {
        return stateLock.withLock { self.currentLanguage }
    }
}
