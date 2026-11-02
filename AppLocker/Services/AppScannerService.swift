//
//  AppScannerService.swift
//  AppLocker
//
//  Created by Doe Phương on 1/11/26.
//

import CoreServices
import Foundation
import Observation

extension Notification.Name {
    static let installedAppsDidUpdate = Notification.Name("installedAppsDidUpdate")
}

@Observable
@MainActor
class AppScannerService: NSObject {
    static let shared = AppScannerService()

    let selfBundlePath = Bundle.main.bundleURL.path

    var installedApps: [InstalledApp] = []

    @ObservationIgnored
    nonisolated(unsafe) var metadataQuery: NSMetadataQuery?
    @ObservationIgnored
    var spotlightTask: Task<Void, Never>?
    @ObservationIgnored
    var appScanTask: Task<Void, Never>?
    @ObservationIgnored
    var cachedFileSystemApps: [InstalledApp] = []
    @ObservationIgnored
    var cachedSpotlightApps: [InstalledApp] = []
    var lastInstalledPathSet: Set<String> = []

    @ObservationIgnored
    var directoryWatcherDebounceTask: Task<Void, Never>?
    @ObservationIgnored
    var directoryWatcherSource: DispatchSourceFileSystemObject?

    override init() {
        super.init()
    }

    deinit {
        spotlightTask?.cancel()
        appScanTask?.cancel()
        directoryWatcherDebounceTask?.cancel()
        directoryWatcherSource?.cancel()
        metadataQuery?.stop()
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        refreshInstalledApps()
        setupSpotlightQuery()
        startApplicationsWatcher()
    }

    // MARK: - Spotlight Query Setup
    func setupSpotlightQuery() {
        guard metadataQuery == nil else { return }

        let query = NSMetadataQuery()
        query.operationQueue = .main
        self.metadataQuery = query

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        query.predicate = NSPredicate(
            format: "(kMDItemContentType == 'com.apple.application-bundle') || (kMDItemFSName ENDSWITH '.app')"
        )
        query.searchScopes = ["/Applications", "/System/Applications"]
        query.start()
    }

    @objc func queryDidUpdate(_ notification: Notification) {
        spotlightTask?.cancel()

        spotlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self = self, !Task.isCancelled else { return }

            let results = self.metadataQuery?.results as? [NSMetadataItem] ?? []
            self.cachedSpotlightApps = self.parseSpotlightResults(results)
            self.mergeAndPublishInstalledApps()
        }
    }

    private func parseSpotlightResults(_ results: [NSMetadataItem]) -> [InstalledApp] {
        results.compactMap { item in
            guard let path = item.value(forAttribute: "kMDItemPath") as? String,
                path != selfBundlePath,
                !path.contains(".app/"),
                path.hasPrefix("/Applications/") || path.hasPrefix("/System/Applications/"),
                let rawName = item.value(forAttribute: "kMDItemDisplayName") as? String
            else { return nil }

            let originalName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let name = (!rawName.isEmpty && rawName != path)
                ? rawName.replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
                : originalName
            let bundleID = item.value(forAttribute: "kMDItemBundleIdentifier") as? String ?? ""
            let source: AppSource = path.hasPrefix("/System") ? .system : .user

            return InstalledApp(
                name: name,
                bundleID: bundleID,
                path: path,
                source: source,
                originalName: originalName
            )
        }
    }

    // MARK: - File System Scanner
    func refreshInstalledApps() {
        appScanTask?.cancel()
        let bundlePath = selfBundlePath

        appScanTask = Task { @MainActor [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) {
                AppScannerService.scanFileSystemApps(excluding: bundlePath)
            }.value

            guard let self = self, !Task.isCancelled else { return }
            self.cachedFileSystemApps = scanned
            self.mergeAndPublishInstalledApps()
        }
    }

    private func mergeAndPublishInstalledApps() {
        var appMap: [String: InstalledApp] = [:]
        let fileManager = FileManager.default

        for app in cachedFileSystemApps where fileManager.fileExists(atPath: app.path) {
            appMap[app.path] = app
        }

        for app in cachedSpotlightApps where fileManager.fileExists(atPath: app.path) {
            if let existing = appMap[app.path] {
                let name = (!app.name.isEmpty && app.name != app.path) ? app.name : existing.name
                let bundleID = !app.bundleID.isEmpty ? app.bundleID : existing.bundleID
                let originalName = existing.originalName ?? app.originalName
                appMap[app.path] = InstalledApp(
                    name: name,
                    bundleID: bundleID,
                    path: app.path,
                    source: existing.source ?? app.source,
                    originalName: originalName
                )
            } else if (app.path.hasPrefix("/Applications/") || app.path.hasPrefix("/System/Applications/"))
                && !app.path.contains(".app/") {
                appMap[app.path] = app
            }
        }

        let installedAppsList = Array(appMap.values)
        if installedAppsList != self.installedApps || self.installedApps.isEmpty {
            self.lastInstalledPathSet = Set(installedAppsList.map { $0.path })
            self.installedApps = installedAppsList
            LockES.shared.handleInstalledAppsChanged(installedAppsList)
            NotificationCenter.default.post(name: .installedAppsDidUpdate, object: nil)
        }
    }

    nonisolated static func scanFileSystemApps(excluding selfBundlePath: String) -> [InstalledApp] {
        let fileManager = FileManager.default
        let excludedExts: Set<String> = ["app", "framework", "plugin", "bundle", "kext", "savedstate"]
        var apps: [InstalledApp] = []
        var seenPaths = Set<String>()
        var visitedDirs = Set<String>()
        var dirsToScan = ["/Applications", "/System/Applications"]

        while !dirsToScan.isEmpty {
            let currentDir = dirsToScan.removeFirst()
            guard visitedDirs.insert(currentDir).inserted,
                let fileNames = try? fileManager.contentsOfDirectory(atPath: currentDir)
            else { continue }

            for fileName in fileNames where !fileName.hasPrefix(".") {
                let fullPath = (currentDir as NSString).appendingPathComponent(fileName)
                if fileName.hasSuffix(".app") {
                    guard fullPath != selfBundlePath,
                        !fullPath.contains(".app/"),
                        !seenPaths.contains(fullPath)
                    else { continue }
                    seenPaths.insert(fullPath)

                    let originalName = (fileName as NSString).deletingPathExtension
                    let meta = InstalledApp.resolveMetadata(at: fullPath, fallback: originalName)
                    let source: AppSource = fullPath.hasPrefix("/System") ? .system : .user
                    apps.append(
                        InstalledApp(
                            name: meta.name,
                            bundleID: meta.bundleID,
                            path: fullPath,
                            source: source,
                            originalName: originalName
                        )
                    )
                } else {
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                        let ext = (fileName as NSString).pathExtension.lowercased()
                        if !excludedExts.contains(ext) {
                            dirsToScan.append(fullPath)
                        }
                    }
                }
            }
        }
        return apps
    }

    // MARK: - Directory Watcher
    func startApplicationsWatcher() {
        guard directoryWatcherSource == nil else { return }
        let descriptor = open("/Applications", O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleApplicationsDirectoryInterrupt()
            }
        }

        source.setCancelHandler {
            close(descriptor)
        }

        self.directoryWatcherSource = source
        source.resume()
    }

    func handleApplicationsDirectoryInterrupt() {
        directoryWatcherDebounceTask?.cancel()
        directoryWatcherDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self = self else { return }
            Logfile.policy.debug(
                "[AppScannerService] /Applications interrupt received. Refreshing installed apps & healing CDHashes..."
            )
            self.refreshInstalledApps()
            LockES.shared.verifyAndHealLockedCDHashes()
        }
    }
}
