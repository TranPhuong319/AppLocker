//
//  AppState+Spotlight.swift
//  AppLocker
//
//  Created by Doe Phương on 16/8/26.
//

import CoreServices
import Foundation

extension AppState {
    func setupSpotlightQuery() {
        let query = NSMetadataQuery()
        query.operationQueue = .main
        self.metadataQuery = query

        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate), name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate), name: .NSMetadataQueryDidUpdate,
            object: query
        )

        query.predicate = NSPredicate(
            format:
                "(kMDItemContentType == 'com.apple.application-bundle') || (kMDItemFSName ENDSWITH '.app')"
        )
        metadataQuery?.searchScopes = ["/Applications", "/System/Applications"]
        metadataQuery?.start()
    }

    func refreshInstalledApps() {
        appScanTask?.cancel()
        let bundlePath = selfBundlePath

        appScanTask = Task { @MainActor [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) {
                AppState.scanFileSystemApps(excluding: bundlePath)
            }.value

            guard let self = self, !Task.isCancelled else { return }
            self.cachedFileSystemApps = scanned
            self.mergeAndPublishInstalledApps()
        }
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
        if installedAppsList != self.manager.allApps || self.manager.allApps.isEmpty {
            self.lastInstalledPathSet = Set(installedAppsList.map { $0.path })
            self.manager.allApps = installedAppsList
            self.refreshAppLists()
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
                    let meta = resolveMetadata(at: fullPath, fallback: originalName)
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

    nonisolated static func resolveMetadata(
        at path: String,
        fallback: String
    ) -> (name: String, bundleID: String) {
        let url = URL(fileURLWithPath: path)
        var name = fallback
        var bundleID = ""

        if let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) {
            if let rawName = MDItemCopyAttribute(mdItem, kMDItemDisplayName) as? String {
                let clean = rawName.replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
                if !clean.isEmpty && clean != path {
                    name = clean
                }
            }
            if let bid = MDItemCopyAttribute(mdItem, kMDItemCFBundleIdentifier) as? String {
                bundleID = bid
            }
        }

        if bundleID.isEmpty || name == fallback {
            if let bundle = Bundle(url: url) {
                if bundleID.isEmpty {
                    bundleID = bundle.bundleIdentifier ?? ""
                }
                if name == fallback {
                    name = localizedBundleName(bundle: bundle, fallback: fallback)
                }
            }
        }

        return (name, bundleID)
    }

    private nonisolated static func localizedBundleName(bundle: Bundle, fallback: String) -> String {
        if let displayName = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
            !displayName.isEmpty {
            return displayName
        }
        if let bundleName = bundle.localizedInfoDictionary?["CFBundleName"] as? String,
            !bundleName.isEmpty {
            return bundleName
        }
        return fallback
    }

    nonisolated static func resolveDisplayName(at path: String, fallback: String) -> String {
        resolveMetadata(at: path, fallback: fallback).name
    }

    func startApplicationsWatcher() {
        guard directoryWatcherSource == nil else { return }
        let descriptor = open("/Applications", O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshInstalledApps()
                self?.refreshAppLists()
            }
        }

        source.setCancelHandler {
            close(descriptor)
        }

        self.directoryWatcherSource = source
        source.resume()
    }
}
