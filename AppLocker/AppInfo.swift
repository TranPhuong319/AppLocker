//
//  AppInfo.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import AppKit

struct AppInfo: Identifiable, Hashable {
    var id: String { bundleID }  // Dùng bundleID làm id ổn định
    let name: String
    let bundleID: String
    let icon: NSImage?
}

