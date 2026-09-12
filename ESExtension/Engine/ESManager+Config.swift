//
//  ESManager+Config.swift
//  ESExtension
//
//  Created by Doe Phương on 6/2/26.
//

import Foundation
import os

private struct LoadedConfigs {
    let cdhashes: [uid_t: Set<String>]
    let bundlePaths: [uid_t: Set<String>]
    let incomingCalls: [uid_t: Bool]
}

extension ESManager {
    static var baseConfigDirectory: String { UserConfig.baseDirectoryURL.path }

    /// Đọc cấu hình từ tất cả các file /Users/Shared/AppLocker/<UID>/config.plist và cập nhật vào bộ nhớ ngay lập tức
    func loadInitialConfigSync() {
        guard let configs = readConfigsFromDisk() else {
            return
        }

        // Atomic Swap
        self.stateLock.withLock {
            self.lockedCDHashes = configs.cdhashes
            self.lockedBundlePaths = configs.bundlePaths
            self.allowIncomingCallsByUID = configs.incomingCalls
        }

        let totalApps = configs.bundlePaths.values.reduce(0) { $0 + $1.count }
        Logfile.endpointSecurity.info(
            """
            [ESConfig] Loaded \(totalApps, privacy: .public) apps for \
            \(configs.cdhashes.count, privacy: .public) users from per-user configs.
            """
        )
    }

    private func readConfigsFromDisk() -> LoadedConfigs? {
        let baseDir = UserConfig.baseDirectoryURL.path
        guard FileManager.default.fileExists(atPath: baseDir) else {
            Logfile.endpointSecurity.debug(
                "[ESConfig] Base config directory not found at \(baseDir, privacy: .public). Skipping load."
            )
            return nil
        }

        var newCDHashes: [uid_t: Set<String>] = [:]
        var newBundlePaths: [uid_t: Set<String>] = [:]
        var newAllowIncomingCalls: [uid_t: Bool] = [:]

        let configs = UserConfig.loadAll()
        for (uid, userConfig) in configs {
            newAllowIncomingCalls[uid] = userConfig.allowIncomingCalls ?? true

            guard !userConfig.isDisabled else { continue }
            let (cdhashes, bundlePaths) = extractHashesAndPaths(from: userConfig.apps)
            newCDHashes[uid] = cdhashes
            newBundlePaths[uid] = bundlePaths
        }

        return LoadedConfigs(
            cdhashes: newCDHashes,
            bundlePaths: newBundlePaths,
            incomingCalls: newAllowIncomingCalls
        )
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

    func startConfigMonitoring() {
        for (_, source) in configMonitorSources {
            source.cancel()
        }
        configMonitorSources.removeAll()

        let baseDir = ESManager.baseConfigDirectory
        guard FileManager.default.fileExists(atPath: baseDir) else {
            Logfile.endpointSecurity.error(
                "[ESConfig] Base config directory does not exist: \(baseDir, privacy: .public)"
            )
            backgroundProcessingQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.startConfigMonitoring()
            }
            return
        }

        // 1. Monitor base directory for new/deleted UID directories
        monitorDirectory(at: baseDir, isBase: true)

        // 2. Monitor each existing UID subdirectory for config changes
        if let subpaths = try? FileManager.default.contentsOfDirectory(atPath: baseDir) {
            for item in subpaths where uid_t(item) != nil {
                let userDirPath = (baseDir as NSString).appendingPathComponent(item)
                monitorDirectory(at: userDirPath, isBase: false)
            }
        }

        Logfile.endpointSecurity.info(
            """
            [ESConfig] Started monitoring base and \(self.configMonitorSources.count - 1, privacy: .public) \
            UID subdirectories.
            """
        )
    }

    private func monitorDirectory(at path: String, isBase: Bool) {
        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            Logfile.endpointSecurity.error(
                "[ESConfig] Failed to open directory for monitoring: \(path, privacy: .public)"
            )
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write],
            queue: backgroundProcessingQueue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.scheduleDebouncedConfigReload(refreshMonitors: isBase)
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        configMonitorSources[path] = source
        source.resume()
    }

    private func scheduleDebouncedConfigReload(refreshMonitors: Bool) {
        configDebounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: backgroundProcessingQueue)
        timer.schedule(deadline: .now() + 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Logfile.endpointSecurity.debug("[ESConfig] Config directory change detected, reloading config...")
            self.loadInitialConfigSync()
            if refreshMonitors {
                self.startConfigMonitoring()
            }
            timer.cancel()
        }
        timer.resume()
        configDebounceTimer = timer
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
            Logfile.endpointSecurity.debug("[ESConfig] ES process language updated to: \(code, privacy: .public)")
        }
    }

    // Read the current language in a thread-safe way.
    func getCurrentLanguage() -> String {
        return stateLock.withLock { self.currentLanguage }
    }
}
