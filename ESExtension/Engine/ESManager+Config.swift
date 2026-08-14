//
//  ESManager+Config.swift
//  ESExtension
//
//  Created by Antigravity on 06/02/26.
//

import Foundation
import os

extension ESManager {
    static let configPath = "/Users/Shared/AppLocker/config.plist"

    /// Đọc cấu hình từ file và cập nhật vào bộ nhớ
    /// Đọc cấu hình từ file và cập nhật vào bộ nhớ ngay lập tức
    func loadInitialConfigSync() {
        let url = URL(fileURLWithPath: ESManager.configPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logfile.endpointSecurity.log("Config file not found at \(ESManager.configPath). Skipping initial load.")
            return
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let (newCDHashes, newBundlePaths) = self.parseConfigData(data)

            // Atomic Swap
            self.stateLock.withLock {
                self.lockedCDHashes = newCDHashes
                self.lockedBundlePaths = newBundlePaths
            }

            let totalApps = newBundlePaths.values.reduce(0) { $0 + $1.count }
            Logfile.endpointSecurity.log(
                "ESManager: Loaded \(totalApps) apps for \(newCDHashes.count) users from config."
            )

        } catch {
            Logfile.endpointSecurity.error("ESManager: Failed to load config: \(error.localizedDescription)")
        }
    }

    private func parseConfigData(_ data: Data) -> ([uid_t: Set<String>], [uid_t: Set<String>]) {
        let decoder = PropertyListDecoder()
        var newCDHashes: [uid_t: Set<String>] = [:]
        var newBundlePaths: [uid_t: Set<String>] = [:]

        let processAppsForUser: (uid_t, [LockedAppConfig]) -> Void = { uid, apps in
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

            newCDHashes[uid] = cdhashes
            newBundlePaths[uid] = bundlePaths
        }

        if let rawConfig = try? decoder.decode([String: UserConfig].self, from: data) {
            for (uidString, userConfig) in rawConfig {
                guard let uid = uid_t(uidString), !userConfig.isDisabled else { continue }
                processAppsForUser(uid, userConfig.apps)
            }
        } else if let oldConfig = try? decoder.decode([String: [LockedAppConfig]].self, from: data) {
            for (uidString, apps) in oldConfig {
                guard let uid = uid_t(uidString) else { continue }
                processAppsForUser(uid, apps)
            }
        }

        return (newCDHashes, newBundlePaths)
    }

    /// Theo dõi thay đổi của thư mục chứa cấu hình để bắt được sự kiện Atomic Write (Rename/Delete)
    func startConfigMonitoring() {
        let configDir = URL(fileURLWithPath: ESManager.configPath).deletingLastPathComponent().path

        configMonitorSource?.cancel()
        configMonitorSource = nil

        let fileDescriptor = open(configDir, O_EVTONLY)

        guard fileDescriptor != -1 else {
            Logfile.endpointSecurity.error("ESManager: Failed to open config directory for monitoring: \(configDir)")
            backgroundProcessingQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.startConfigMonitoring()
            }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write], // Directory write covers file create/delete/rename
            queue: backgroundProcessingQueue
        )

        var debounceTimer: DispatchSourceTimer?

        source.setEventHandler { [weak self] in
            guard let self = self else { return }

            debounceTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.backgroundProcessingQueue)
            timer.schedule(deadline: .now() + 0.05) // Debounce 50ms for instant update
            timer.setEventHandler { [weak self] in
                Logfile.endpointSecurity.log("ESManager: Directory change detected, reloading config...")
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
        Logfile.endpointSecurity.log("ESManager: Started directory monitoring for \(configDir)")
    }

    // MARK: - Language Configuration

    // Force the extension process to use a specific language.
    @objc func updateLanguage(to code: String) {
        guard isCurrentConnectionAuthenticated() else {
            Logfile.endpointSecurity.error("Unauthorized call to updateLanguage")
            return
        }
        stateLock.withLock {
            self.currentLanguage = code
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            Logfile.endpointSecurity.log("ES Process language forced to: \(code)")
        }
    }

    // Read the current language in a thread-safe way.
    func getCurrentLanguage() -> String {
        return stateLock.withLock { self.currentLanguage }
    }
}
