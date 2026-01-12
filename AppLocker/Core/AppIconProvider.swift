//
//  AppIconProvider.swift
//  AppLocker
//
//  Created by Doe Phương on 11/1/26.
//

import AppKit
import Foundation

class AppIconProvider {
    static let shared = AppIconProvider()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        // Giới hạn bộ nhớ cache để tránh tốn tài nguyên quá mức
        cache.countLimit = 200
    }

    func icon(forPath path: String, size: CGFloat = 32) -> NSImage {
        let key = "\(path)_\(size)" as NSString

        if let cachedIcon = cache.object(forKey: key) {
            return cachedIcon
        }

        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: size, height: size)

        cache.setObject(icon, forKey: key)
        return icon
    }

    func clearCache() {
        cache.removeAllObjects()
    }
}
