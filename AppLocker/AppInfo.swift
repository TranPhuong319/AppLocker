//
//  AppInfo.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import AppKit

struct AppInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let bundleID: String
    let icon: NSImage?
}
