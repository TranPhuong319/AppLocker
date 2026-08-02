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
        let appBundlePath = resolveAppBundlePath(from: path)
        let key = "\(appBundlePath)_\(size)" as NSString

        if let cachedIcon = cache.object(forKey: key) {
            return cachedIcon
        }

        let icon = NSWorkspace.shared.icon(forFile: appBundlePath)
        icon.size = NSSize(width: size, height: size)

        cache.setObject(icon, forKey: key)
        return icon
    }

    private func resolveAppBundlePath(from path: String) -> String {
        var url = URL(fileURLWithPath: path)
        while url.path != "/" && url.pathComponents.count > 1 {
            if url.pathExtension.lowercased() == "app" {
                return url.path
            }
            url = url.deletingLastPathComponent()
        }
        return path
    }

    func clearCache() {
        cache.removeAllObjects()
    }
}
