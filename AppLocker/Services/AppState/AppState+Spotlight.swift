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

    @objc func queryDidUpdate(_ notification: Notification) {
        spotlightTask?.cancel()

        spotlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self = self, !Task.isCancelled else { return }

            let results = self.metadataQuery?.results as? [NSMetadataItem] ?? []

            let installedAppsList: [InstalledApp] = results.compactMap { item in
                guard let path = item.value(forAttribute: "kMDItemPath") as? String,
                    path != self.selfBundlePath,
                    !path.contains(".app/"),
                    let rawName = item.value(forAttribute: "kMDItemDisplayName") as? String
                else { return nil }

                let name = rawName.replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
                let bundleID = item.value(forAttribute: "kMDItemBundleIdentifier") as? String ?? ""
                let source: AppSource = path.hasPrefix("/System") ? .system : .user

                return InstalledApp(name: name, bundleID: bundleID, path: path, source: source)
            }

            let newPathSet = Set(installedAppsList.map { $0.path })
            if newPathSet != self.lastInstalledPathSet {
                self.lastInstalledPathSet = newPathSet
                self.manager.allApps = installedAppsList
                self.refreshAppLists()
            }
        }
    }
}
