//
//  AppInfo.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//


import AppKit

//struct AppInfoUI: Identifiable, Hashable {
//    var id: String { bundleID + "::" + path } //  duy nhất
//    let name: String
//    let bundleID: String
//    let icon: NSImage?
//    let path: String
//}

struct LockedAppInfo: Codable {
    let name: String
    let execFile: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case execFile = "ExecFile"
    }
}



