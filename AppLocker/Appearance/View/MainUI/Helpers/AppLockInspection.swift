//
//  AppLockInspection.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import Foundation

func isAppStubbedAsLocked(_ appURL: URL, appState: AppState) -> Bool {
    let resourceDir = appURL.appendingPathComponent("Contents/Resources")

    guard let subApps = try? FileManager.default.contentsOfDirectory(
        at: resourceDir, includingPropertiesForKeys: nil) else {
        return false
    }

    for subApp in subApps where subApp.pathExtension == "app" {
        let infoPlist = subApp.appendingPathComponent("Contents/Info.plist")
        guard
            let infoDict = NSDictionary(contentsOf: infoPlist) as? [String: Any],
            infoDict["CFBundleIdentifier"] != nil
        else {
            continue
        }

        if appState.manager.lockedApps.keys.contains(subApp.path) {
            return true
        }
    }

    return false
}
