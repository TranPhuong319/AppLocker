//
//  AppOverlayController.swift
//  AppLocker
//
//  Created by Doe Phương on 01/08/2025.
//


import Cocoa
import ApplicationServices

class AppOverlayController {
    private var overlays: [String: NSWindow] = [:]
    private var timer: Timer?

    func startMonitoring(lockedBundleIDs: [String]) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            for app in NSWorkspace.shared.runningApplications {
                guard let bundleID = app.bundleIdentifier else { continue }
                if lockedBundleIDs.contains(bundleID) {
                    self.ensureOverlay(for: app)
                } else {
                    self.removeOverlay(for: app)
                }
            }
        }
    }

    func ensureOverlay(for app: NSRunningApplication) {
        guard overlays[app.bundleIdentifier ?? ""] == nil,
              let frame = getMainWindowFrame(of: app) else { return }

        let window = NSWindow(contentRect: frame,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false)
        window.level = .mainMenu + 1
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.4)
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
        window.makeKeyAndOrderFront(nil)

        // Add optional UI: label, button, Touch ID unlock, etc.
        overlays[app.bundleIdentifier ?? ""] = window
    }

    func removeOverlay(for app: NSRunningApplication) {
        guard let id = app.bundleIdentifier,
              let overlay = overlays[id] else { return }
        overlay.close()
        overlays.removeValue(forKey: id)
    }

    func getMainWindowFrame(of app: NSRunningApplication) -> CGRect? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: AnyObject?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        guard let windows = value as? [AXUIElement], let window = windows.first else { return nil }

        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posVal) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeVal) == .success,
              let posAX = posVal as? AXValue, let sizeAX = sizeVal as? AXValue else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posAX, .cgPoint, &position)
        AXValueGetValue(sizeAX, .cgSize, &size)

        return CGRect(origin: position, size: size)
    }
}
