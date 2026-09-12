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

        let fileExists = FileManager.default.fileExists(atPath: appBundlePath)
        let rawIcon: NSImage
        if fileExists {
            rawIcon = NSWorkspace.shared.icon(forFile: appBundlePath)
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
            let cost = Int(size * size * 4 * 4)
            cache.setObject(rasterized, forKey: key, cost: cost)
        }
        return rasterized
    }

    func invalidateIcon(forPath path: String) {
        let appBundlePath = resolveAppBundlePath(from: path)
        for size in [16, 24, 32, 48, 64] {
            cache.removeObject(forKey: "\(appBundlePath)_\(size)" as NSString)
        }
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

        let imgWidth = max(image.size.width, 1)
        let imgHeight = max(image.size.height, 1)
        let scaleFactor = min(targetSize / imgWidth, targetSize / imgHeight)
        let drawWidth = imgWidth * scaleFactor
        let drawHeight = imgHeight * scaleFactor
        let destRect = NSRect(
            x: (targetSize - drawWidth) / 2.0,
            y: (targetSize - drawHeight) / 2.0,
            width: drawWidth,
            height: drawHeight
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        image.draw(
            in: destRect,
            from: .zero,
            operation: .sourceOver,
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
}
