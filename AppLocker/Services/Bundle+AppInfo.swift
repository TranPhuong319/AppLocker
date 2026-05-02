//
//  Bundle+AppInfo.swift
//  AppLocker
//
//  Created by Doe Phương on 2/5/26.
//

import Foundation
import AppKit

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

    var detailedVersion: String {
        "Version \(appVersion) (Build \(appBuild))"
    }

    var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "No information available"
    }
    
    var appIcon: NSImage {
        NSApplication.shared.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
}
