//
//  AppInfo.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit
import CoreServices

enum AppSource: String, Sendable {
    case user = "Applications"
    case system = "System"
}

struct InstalledApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let originalName: String?
    let bundleID: String
    let path: String
    let source: AppSource?

    init(
        name: String,
        bundleID: String,
        path: String,
        source: AppSource? = nil,
        originalName: String? = nil
    ) {
        self.id = path
        self.name = name
        self.originalName = originalName
        self.bundleID = bundleID
        self.path = path
        self.source = source
    }
}

// MARK: - Mock Data for Previews
extension InstalledApp {
    static let mockChrome = InstalledApp(
        name: "Google Chrome",
        bundleID: "com.google.Chrome",
        path: "/Applications/Google Chrome.app",
        source: .user
    )
    static let mockSafari = InstalledApp(
        name: "Safari",
        bundleID: "com.apple.Safari",
        path: "/System/Applications/Safari.app",
        source: .system
    )
    static let mockVSCode = InstalledApp(
        name: "Visual Studio Code",
        bundleID: "com.microsoft.VSCode",
        path: "/Applications/Visual Studio Code.app",
        source: .user
    )
    static let mockFinder = InstalledApp(
        name: "Finder",
        bundleID: "com.apple.finder",
        path: "/System/Library/CoreServices/Finder.app",
        source: .system
    )

    static var allMocks: [InstalledApp] {
        [mockChrome, mockSafari, mockVSCode, mockFinder]
    }
}

// MARK: - App Metadata Resolution
extension InstalledApp {
    public nonisolated static func resolveMetadata(
        at path: String,
        fallback: String
    ) -> (name: String, bundleID: String) {
        let bundleURL = URL(fileURLWithPath: path).enclosingAppBundleURL
        let resolvedPath = bundleURL.path
        var name = fallback
        var bundleID = ""

        if let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, bundleURL as CFURL) {
            if let rawName = MDItemCopyAttribute(mdItem, kMDItemDisplayName) as? String {
                let clean = rawName.replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
                if !clean.isEmpty && clean != resolvedPath {
                    name = clean
                }
            }
            if let bid = MDItemCopyAttribute(mdItem, kMDItemCFBundleIdentifier) as? String {
                bundleID = bid
            }
        }

        if bundleID.isEmpty || name == fallback {
            if let bundle = Bundle(url: bundleURL) {
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

    public nonisolated static func resolveDisplayName(at path: String, fallback: String) -> String {
        resolveMetadata(at: path, fallback: fallback).name
    }
}

// MARK: - Bundle App Metadata
extension Bundle {
    var appName: String {
        object(forInfoDictionaryKey: "CFBundleName") as? String ?? "AppLocker"
    }

    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var appBuild: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var fullVersion: String {
        "\(appVersion) (\(appBuild))"
    }

    var copyright: String {
        object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "No information available"
    }

    @MainActor
    var appIcon: NSImage {
        NSApplication.shared.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
}

// MARK: - Pasteboard Helper
extension NSPasteboard {
    public func copyText(_ text: String) {
        clearContents()
        setString(text, forType: .string)
    }
}
