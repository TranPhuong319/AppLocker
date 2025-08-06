//
//  AppInfo.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import AppKit

struct AppInfoUI: Identifiable, Hashable {
    var id: String { bundleID }  // Dùng bundleID làm id ổn định
    let name: String
    let bundleID: String
    let icon: NSImage?
}

    struct LockedAppInfo: Codable {
        let name: String
        let execFile: String

        enum CodingKeys: String, CodingKey {
            case name = "Name"
            case execFile = "ExecFile"
        }
    }



