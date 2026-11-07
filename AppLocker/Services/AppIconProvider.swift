//
//  AppIconProvider.swift
//  AppLocker
//
//  Created by Doe Phương on 11/1/26.
//

import AppKit
import Foundation

@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private let cache = NSCache<NSString, NSImage>()
    private var placeholderCache: [Int: NSImage] = [:]

    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 50 * 1024 * 1024
    }

    func defaultPlaceholder(size: CGFloat = 32) -> NSImage {
        let intSize = Int(size)
        if let cached = placeholderCache[intSize] {
            return cached
        }
        let rawIcon = NSWorkspace.shared.icon(for: .applicationBundle)
        let rasterized = rasterize(image: rawIcon, targetSize: size)
        placeholderCache[intSize] = rasterized
        return rasterized
    }

    func preloadIcons(for paths: [String], size: CGFloat = 32) {
        for path in paths {
            _ = icon(for: path, size: size)
        }
    }

    func cachedIcon(for path: String, size: CGFloat = 32) -> NSImage? {
        let appBundlePath = resolveAppBundlePath(from: path)
        let key = "\(appBundlePath)_\(Int(size))" as NSString
        return cache.object(forKey: key)
    }

    func icon(for path: String, size: CGFloat = 32) -> NSImage {
        let appBundlePath = resolveAppBundlePath(from: path)
        let key = "\(appBundlePath)_\(Int(size))" as NSString

        if let cachedIcon = cache.object(forKey: key) {
            return cachedIcon
        }

        let fileExists = FileManager.default.fileExists(atPath: appBundlePath)
        let rawIcon: NSImage
        if fileExists {
            rawIcon = NSWorkspace.shared.icon(forFile: appBundlePath)
            rawIcon.size = NSSize(width: 64, height: 64)
        } else {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
                .applying(.init(hierarchicalColor: .secondaryLabelColor))
            rawIcon = NSImage(systemSymbolName: "xmark.app.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig)
                ?? NSWorkspace.shared.icon(for: .applicationBundle)
        }
        let rasterized = rasterize(image: rawIcon, targetSize: size)

        if !fileExists {
            rasterized.isTemplate = true
        }

        if fileExists {
            let pixelSize = min(Int(size * 2.0), 64)
            let cost = pixelSize * pixelSize * 4
            cache.setObject(rasterized, forKey: key, cost: cost)
        }
        return rasterized
    }

    func invalidateIcon(for path: String) {
        let appBundlePath = resolveAppBundlePath(from: path)
        for size in [16, 24, 32, 36, 48, 64] {
            cache.removeObject(forKey: "\(appBundlePath)_\(size)" as NSString)
        }
    }

    private func rasterize(image: NSImage, targetSize: CGFloat) -> NSImage {
        let targetSizeObj = NSSize(width: targetSize, height: targetSize)
        return NSImage(size: targetSizeObj, flipped: false) { destRect in
            image.draw(in: destRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }

    private func resolveAppBundlePath(from path: String) -> String {
        URL(fileURLWithPath: path).enclosingAppBundleURL.path
    }
}
