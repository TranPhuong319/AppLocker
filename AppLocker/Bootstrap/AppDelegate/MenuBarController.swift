//
//  MenuBarController.swift
//  AppLocker
//
//  Created by Doe Phương on 14/11/26.
//

import AppKit
import Symbols

private final class MenuBarImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusImageView: NSImageView?
    private var currentMenuBarSymbol: String?
    private var currentThemeAppearance: NSAppearance?
    private var isSetup = false

    var statusItemWindow: NSWindow? {
        statusItem?.button?.window
    }

    func setup(appearance: NSAppearance?) {
        currentThemeAppearance = appearance

        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }

        if let button = statusItem?.button, statusImageView == nil {
            let imageView = MenuBarImageView(frame: button.bounds)
            imageView.autoresizingMask = [.width, .height]
            imageView.imageScaling = .scaleProportionallyDown
            imageView.imageAlignment = .alignCenter
            imageView.appearance = nil
            button.appearance = nil
            button.addSubview(imageView)
            statusImageView = imageView
        }

        updateIcon()

        let menu = NSMenu()
        menu.appearance = currentThemeAppearance
        menu.delegate = self
        statusItem?.menu = menu

        guard !isSetup else { return }
        isSetup = true

        NotificationCenter.default.addObserver(
            forName: .appLockerPendingUpdateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateIcon()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .protectionStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateIcon()
            }
        }
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        currentThemeAppearance = appearance

        statusItem?.button?.appearance = nil
        statusImageView?.appearance = nil
        statusItem?.button?.window?.appearance = nil
        statusItem?.button?.needsDisplay = true
        statusImageView?.needsDisplay = true
        statusItem?.menu?.appearance = appearance
    }

    func updateIcon() {
        let symbolName: String
        if !ExtensionInstaller.shared.isInstalled {
            symbolName = "lock.trianglebadge.exclamationmark.fill"
        } else if LockES.shared.isProtectionDisabled {
            symbolName = "lock.open.fill"
        } else if AppUpdater.shared.hasAvailableUpdate {
            symbolName = "arrowshape.down.circle"
        } else {
            symbolName = "lock.fill"
        }

        guard symbolName != currentMenuBarSymbol else { return }
        let isFirst = (currentMenuBarSymbol == nil)
        currentMenuBarSymbol = symbolName

        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AppLocker") else { return }
        image.isTemplate = true

        if let statusImageView {
            if isFirst {
                statusImageView.image = image
            } else if #available(macOS 15.0, *) {
                statusImageView.setSymbolImage(image, contentTransition: .replace.magic(fallback: .downUp.byLayer))
            } else {
                statusImageView.setSymbolImage(image, contentTransition: .replace.downUp.byLayer)
            }
        } else if let button = statusItem?.button {
            button.image = image
        }
    }

    func bounceIcon() {
        statusImageView?.addSymbolEffect(BounceSymbolEffect.bounce)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.appearance = currentThemeAppearance
        menu.removeAllItems()

        addHeaderMenuItems(to: menu)
        addPrimaryMenuItems(to: menu)
        addMaintenanceMenuItems(to: menu)
    }

    private func addHeaderMenuItems(to menu: NSMenu) {
        updateIcon()

        let infoItem = NSMenuItem.sectionHeader(
            title: "AppLocker v\(Bundle.main.fullVersion)"
        )
        menu.addItem(infoItem)

        if LockES.shared.isProtectionDisabled {
            let resumeShortcut = HotKeyShortcut.currentResumeProtection
            let resumeItem = NSMenuItem(
                title: String(localized: "Resume Protection"),
                action: #selector(AppDelegate.resumeProtection),
                keyEquivalent: resumeShortcut?.keyEquivalent ?? ""
            )
            if let resumeShortcut {
                resumeItem.keyEquivalentModifierMask = resumeShortcut.modifierFlags
            }
            resumeItem.image = NSImage(
                systemSymbolName: "lock.fill",
                accessibilityDescription: String(localized: "Resume Protection")
            )
            menu.addItem(resumeItem)
        }

        if AppUpdater.shared.hasAvailableUpdate, let ver = AppUpdater.shared.availableUpdateVersion {
            let updateNoticeItem = NSMenuItem(
                title: String(format: String(localized: "Version %@ available"), ver),
                action: #selector(AppDelegate.checkForUpdates),
                keyEquivalent: ""
            )
            updateNoticeItem.image = NSImage(
                systemSymbolName: "arrow.down.circle.fill",
                accessibilityDescription: "Update Available"
            )
            menu.addItem(updateNoticeItem)
        }

        if !ExtensionInstaller.shared.isInstalled {
            let statusItem = NSMenuItem(
                title: String(localized: "System Extension Inactive"),
                action: #selector(AppDelegate.openSystemSettingsForExtension),
                keyEquivalent: ""
            )
            statusItem.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: nil
            )
            menu.addItem(statusItem)
        }

        menu.addItem(.separator())
    }

    private func addPrimaryMenuItems(to menu: NSMenu) {
        let manageShortcut = HotKeyShortcut.currentAppList
        let manageItem = NSMenuItem(
            title: String(localized: "Manage the application list") + "…",
            action: #selector(AppDelegate.openAppList),
            keyEquivalent: manageShortcut?.keyEquivalent ?? ""
        )
        if let manageShortcut {
            manageItem.keyEquivalentModifierMask = manageShortcut.modifierFlags
        }
        manageItem.image = NSImage(systemSymbolName: "lock.app.dashed", accessibilityDescription: nil)
        menu.addItem(manageItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: String(localized: "Settings") + "…",
            action: #selector(AppDelegate.openSettings),
            keyEquivalent: ","
        ))

        menu.addItem(.separator())
    }

    private func addMaintenanceMenuItems(to menu: NSMenu) {
        let updateItem = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(AppDelegate.checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.image = NSImage(
            systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90",
            accessibilityDescription: nil
        )
        menu.addItem(updateItem)

        let aboutItem = NSMenuItem(
            title: String(localized: "About AppLocker"),
            action: #selector(AppDelegate.showAboutWindow),
            keyEquivalent: ""
        )
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(
            title: String(localized: "Uninstall AppLocker") + "…",
            action: #selector(AppDelegate.uninstall),
            keyEquivalent: ""
        )
        uninstallItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(uninstallItem)

        let resetItem = NSMenuItem(
            title: String(localized: "Reset AppLocker") + "…",
            action: #selector(AppDelegate.resetApp),
            keyEquivalent: ""
        )
        resetItem.image = NSImage(systemSymbolName: "arrow.counterclockwise.circle", accessibilityDescription: nil)
        resetItem.keyEquivalentModifierMask = [.option]
        resetItem.isAlternate = true
        menu.addItem(resetItem)

        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: String(localized: "Quit AppLocker"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        #endif
    }
}
