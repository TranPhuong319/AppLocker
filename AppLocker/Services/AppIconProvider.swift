//
//  AppIconProvider.swift
//  AppLocker
//
//  Created by Doe Phương on 11/1/26.
//

import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private static let iconAppearanceDidChangeNotification = NSNotification.Name(
        "NSWorkspaceIconAppearanceConfigurationDidChangeNotification"
    )
    private static let interfaceThemeDidChangeNotification = NSNotification.Name(
        "AppleInterfaceThemeChangedNotification"
    )

    private(set) var revision: Int = 0
    @ObservationIgnored private let cache = NSCache<NSString, NSImage>()
    @ObservationIgnored private var placeholderCache: [Int: NSImage] = [:]
    @ObservationIgnored private var lastAppearanceSignature: [String: String] = [:]
    @ObservationIgnored private nonisolated(unsafe) var iconAppearanceObserver: NSObjectProtocol?
    @ObservationIgnored private nonisolated(unsafe) var interfaceThemeObserver: NSObjectProtocol?
    @ObservationIgnored private nonisolated(unsafe) var appDidBecomeActiveObserver: NSObjectProtocol?

    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 50 * 1024 * 1024
        lastAppearanceSignature = Self.currentAppearanceSignature()
        registerAppearanceObservers()
    }

    deinit {
        if let iconAppearanceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(iconAppearanceObserver)
        }
        if let interfaceThemeObserver {
            DistributedNotificationCenter.default().removeObserver(interfaceThemeObserver)
        }
        if let appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
        }
    }

    func defaultPlaceholder(size: CGFloat = 32) -> NSImage {
        _ = revision
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
        let appBundlePath = Self.resolveAppBundlePath(from: path)
        let key = "\(appBundlePath)_\(Int(size))" as NSString
        return cache.object(forKey: key)
    }

    /// Asynchronously loads and rasterizes an application icon off `@MainActor` on cache miss.
    func loadIcon(for path: String, size: CGFloat = 32) async -> NSImage {
        let appBundlePath = Self.resolveAppBundlePath(from: path)
        let key = "\(appBundlePath)_\(Int(size))" as NSString

        if let cachedIcon = cache.object(forKey: key) {
            return cachedIcon
        }

        let decoded: (exists: Bool, cgImage: CGImage?) = await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: appBundlePath) else {
                return (false, nil)
            }
            let rawIcon = NSWorkspace.shared.icon(forFile: appBundlePath)
            rawIcon.size = NSSize(width: 64, height: 64)
            return (true, Self.rasterizeToCGImage(image: rawIcon, targetSize: size))
        }.value

        if let rechecked = cache.object(forKey: key) {
            return rechecked
        }

        guard decoded.exists, let cgImage = decoded.cgImage else {
            return defaultPlaceholder(size: size)
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        let pixelSize = min(Int(size * 2.0), 64)
        cache.setObject(image, forKey: key, cost: pixelSize * pixelSize * 4)
        return image
    }

    func icon(for path: String, size: CGFloat = 32) -> NSImage {
        let appBundlePath = Self.resolveAppBundlePath(from: path)
        let key = "\(appBundlePath)_\(Int(size))" as NSString

        if let cachedIcon = cache.object(forKey: key) {
            return cachedIcon
        }

        guard FileManager.default.fileExists(atPath: appBundlePath) else {
            return defaultPlaceholder(size: size)
        }

        let rawIcon = NSWorkspace.shared.icon(forFile: appBundlePath)
        rawIcon.size = NSSize(width: 64, height: 64)
        let rasterized: NSImage
        if let cgImage = Self.rasterizeToCGImage(image: rawIcon, targetSize: size) {
            rasterized = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        } else {
            rasterized = rasterize(image: rawIcon, targetSize: size)
        }

        let pixelSize = min(Int(size * 2.0), 64)
        let cost = pixelSize * pixelSize * 4
        cache.setObject(rasterized, forKey: key, cost: cost)
        return rasterized
    }

    func invalidateIcon(for path: String) {
        let appBundlePath = Self.resolveAppBundlePath(from: path)
        for size in [16, 24, 32, 36, 48, 64] {
            cache.removeObject(forKey: "\(appBundlePath)_\(size)" as NSString)
        }
        revision &+= 1
    }

    func invalidateAllIcons() {
        cache.removeAllObjects()
        placeholderCache.removeAll()
        lastAppearanceSignature = Self.currentAppearanceSignature()
        revision &+= 1
        Logfile.app.debug(
            "[AppIconProvider] Invalidated all cached icons (revision=\(self.revision, privacy: .public))"
        )
    }

    private func invalidateIconsIfAppearanceChanged() {
        let signature = Self.currentAppearanceSignature()
        guard signature != lastAppearanceSignature else { return }
        invalidateAllIcons()
    }

    private func registerAppearanceObservers() {
        // Tier 2: AppKit undocumented workspace notification for live macOS 26 icon style updates
        iconAppearanceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: Self.iconAppearanceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateAllIcons()
            }
        }

        // Tier 1: System Light/Dark transitions & foreground activation fallback when Tier 2 is unavailable
        interfaceThemeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.interfaceThemeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateIconsIfAppearanceChanged()
            }
        }

        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateIconsIfAppearanceChanged()
            }
        }
    }

    private nonisolated static func currentAppearanceSignature() -> [String: String] {
        let domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        var signature: [String: String] = [:]
        for (key, value) in domain where key.hasPrefix("AppleIcon")
            || key == "AppleInterfaceStyle"
            || key == "AppleAccentColor" {
            signature[key] = String(describing: value)
        }
        return signature
    }

    private func rasterize(image: NSImage, targetSize: CGFloat) -> NSImage {
        let targetSizeObj = NSSize(width: targetSize, height: targetSize)
        return NSImage(size: targetSizeObj, flipped: false) { destRect in
            image.draw(in: destRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }

    private nonisolated static func rasterizeToCGImage(image: NSImage, targetSize: CGFloat) -> CGImage? {
        let pixelDim = max(Int(targetSize * 2.0), 1)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: pixelDim,
                  height: pixelDim,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        image.draw(
            in: NSRect(x: 0, y: 0, width: CGFloat(pixelDim), height: CGFloat(pixelDim)),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private nonisolated static func resolveAppBundlePath(from path: String) -> String {
        URL(fileURLWithPath: path).enclosingAppBundleURL.path
    }
}
