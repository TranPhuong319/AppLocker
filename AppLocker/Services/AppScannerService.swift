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
final class AppScannerService: NSObject {
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
    var directoryWatcherDebounceTask: Task<Void, Never>?
    @ObservationIgnored
    var directoryWatcherSources: [DispatchSourceFileSystemObject] = []

    override init() {
        super.init()
    }

    deinit {
        spotlightTask?.cancel()
        appScanTask?.cancel()
        directoryWatcherDebounceTask?.cancel()
        directoryWatcherSources.forEach { $0.cancel() }
        metadataQuery?.stop()
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        refreshInstalledApps()
        startApplicationsWatchers()
        setupSpotlightQuery()
    }

    // MARK: - Primary Source: Kernel kqueue Watchers on /Applications & /System/Applications

    func startApplicationsWatchers(paths: [String] = ["/Applications", "/System/Applications"]) {
        guard directoryWatcherSources.isEmpty else { return }

        for path in paths {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .rename, .delete, .attrib],
                queue: .main
            )

            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.handleDirectoryInterrupt(for: path)
                }
            }

            source.setCancelHandler {
                close(descriptor)
            }

            directoryWatcherSources.append(source)
            source.resume()
        }
    }

    func handleDirectoryInterrupt(for path: String) {
        directoryWatcherDebounceTask?.cancel()
        directoryWatcherDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            Logfile.policy.debug(
                "[AppScannerService] \(path, privacy: .public) interrupt received. Refreshing installed apps..."
            )
            self.refreshInstalledApps()
            LockES.shared.verifyAndHealLockedCDHashes()
        }
    }

    // MARK: - Fast 1-Pass Shallow Scan directly from VFS

    func refreshInstalledApps() {
        appScanTask?.cancel()
        let bundlePath = selfBundlePath

        appScanTask = Task { @MainActor [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) {
                AppScannerService.scanApplicationsDirectories(excluding: bundlePath)
            }.value

            guard let self, !Task.isCancelled else { return }
            self.publishInstalledApps(scanned)
        }
    }

    nonisolated static func scanApplicationsDirectories(
        directories: [String] = ["/Applications", "/System/Applications", "/System/Applications/Utilities"],
        excluding selfBundlePath: String = ""
    ) -> [InstalledApp] {
        let fileManager = FileManager.default
        var apps: [InstalledApp] = []
        var seenPaths = Set<String>()

        for dir in directories {
            guard let fileNames = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
            for fileName in fileNames where fileName.hasSuffix(".app") && !fileName.hasPrefix(".") {
                let fullPath = (dir as NSString).appendingPathComponent(fileName)
                guard fullPath != selfBundlePath, !seenPaths.contains(fullPath) else { continue }
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
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Secondary Source: Spotlight NSMetadataQuery (Metadata Refinement)

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
            guard let self, !Task.isCancelled else { return }

            let results = self.metadataQuery?.results as? [NSMetadataItem] ?? []
            let parsed = self.parseSpotlightResults(results)
            self.refineWithSpotlightMetadata(parsed)
        }
    }

    nonisolated func parseSpotlightResults(_ results: [NSMetadataItem]) -> [InstalledApp] {
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

    func refineWithSpotlightMetadata(_ spotlightApps: [InstalledApp]) {
        guard !spotlightApps.isEmpty else { return }
        var currentMap = Dictionary(uniqueKeysWithValues: installedApps.map { ($0.path, $0) })
        var updated = false

        for app in spotlightApps {
            if let existing = currentMap[app.path] {
                let nameChanged = !app.name.isEmpty && app.name != existing.name
                let bundleIDAdded = existing.bundleID.isEmpty && !app.bundleID.isEmpty
                if nameChanged || bundleIDAdded {
                    currentMap[app.path] = InstalledApp(
                        name: nameChanged ? app.name : existing.name,
                        bundleID: !app.bundleID.isEmpty ? app.bundleID : existing.bundleID,
                        path: existing.path,
                        source: existing.source,
                        originalName: existing.originalName
                    )
                    updated = true
                }
            } else {
                currentMap[app.path] = app
                updated = true
            }
        }

        if updated {
            let sorted = Array(currentMap.values).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            publishInstalledApps(sorted)
        }
    }

    func publishInstalledApps(_ newApps: [InstalledApp]) {
        if newApps != self.installedApps || self.installedApps.isEmpty {
            self.installedApps = newApps
            LockES.shared.handleInstalledAppsChanged(newApps)
            NotificationCenter.default.post(name: .installedAppsDidUpdate, object: nil)
        }
    }
}
