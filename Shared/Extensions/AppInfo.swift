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

// MARK: - Mock Data for Previews
extension InstalledApp {
    static let mockChrome = InstalledApp(name: "Google Chrome", bundleID: "com.google.Chrome", path: "/Applications/Google Chrome.app", source: .user)
    static let mockSafari = InstalledApp(name: "Safari", bundleID: "com.apple.Safari", path: "/System/Applications/Safari.app", source: .system)
    static let mockVSCode = InstalledApp(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode", path: "/Applications/Visual Studio Code.app", source: .user)
    static let mockFinder = InstalledApp(name: "Finder", bundleID: "com.apple.finder", path: "/System/Library/CoreServices/Finder.app", source: .system)

    static var allMocks: [InstalledApp] {
        [mockChrome, mockSafari, mockVSCode, mockFinder]
    }
}
