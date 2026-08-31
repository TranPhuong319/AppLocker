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

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 5 * 1024 * 1024
    }

    func cachedIcon(forPath path: String, size: CGFloat = 32) -> NSImage? {
        let appBundlePath = resolveAppBundlePath(from: path)
        let key = "\(appBundlePath)_\(Int(size))" as NSString
        return cache.object(forKey: key)
    }

    func icon(forPath path: String, size: CGFloat = 32) -> NSImage {
        let appBundlePath = resolveAppBundlePath(from: path)
        let key = "\(appBundlePath)_\(Int(size))" as NSString

        if let cachedIcon = cache.object(forKey: key) {
            return cachedIcon
        }

        let rawIcon = NSWorkspace.shared.icon(forFile: appBundlePath)
        let rasterized = rasterize(image: rawIcon, targetSize: size)

        let cost = Int(size * size * 4 * 4)
        cache.setObject(rasterized, forKey: key, cost: cost)
        return rasterized
    }

    private func rasterize(image: NSImage, targetSize: CGFloat) -> NSImage {
        let scale: CGFloat = 2.0
        let pixelWidth = Int(targetSize * scale)
        let pixelHeight = Int(targetSize * scale)

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            image.size = NSSize(width: targetSize, height: targetSize)
            return image
        }

        bitmapRep.size = NSSize(width: targetSize, height: targetSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        image.draw(
            in: NSRect(x: 0, y: 0, width: targetSize, height: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        let resizedImage = NSImage(size: NSSize(width: targetSize, height: targetSize))
        resizedImage.addRepresentation(bitmapRep)
        return resizedImage
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
