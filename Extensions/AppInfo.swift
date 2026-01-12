//
//  AppInfo.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit

enum AppSource: String {
    case user = "Applications"
    case system = "System"
}

struct InstalledApp: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String
    let path: String
    let source: AppSource?

    init(name: String, bundleID: String, path: String, source: AppSource? = nil) {
        self.id = path
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.source = source
    }
}
