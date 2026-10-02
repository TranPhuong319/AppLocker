//
//  AppDelegate+MenuBar.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit
import Symbols

private final class MenuBarImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
extension AppDelegate: NSMenuDelegate {
    func setupMenuBar() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }

        if let button = statusItem?.button, statusImageView == nil {
            let imageView = MenuBarImageView(frame: button.bounds)
            imageView.autoresizingMask = [.width, .height]
            imageView.imageScaling = .scaleProportionallyDown
            imageView.imageAlignment = .alignCenter
            button.addSubview(imageView)
            statusImageView = imageView
        }

        updateMenuBarIcon()

        let menu = NSMenu()
        menu.appearance = NSApp.appearance
        menu.delegate = self
        statusItem?.menu = menu

        NotificationCenter.default.addObserver(
            forName: .appLockerPendingUpdateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMenuBarIcon()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .protectionStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMenuBarIcon()
            }
        }
    }

    func updateMenuBarIcon() {
        let symbolName: String
        if !ExtensionInstaller.shared.isInstalled {
            symbolName = "lock.trianglebadge.exclamationmark.fill"
        } else if AppState.shared.manager.isProtectionDisabled {
            symbolName = "lock.open.fill"
        } else {
            symbolName = "lock.fill"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AppLocker")
        image?.isTemplate = true
        if let statusImageView {
            statusImageView.image = image
        } else if let button = statusItem?.button {
            button.image = image
        }
    }

    func bounceMenuBarIcon() {
        statusImageView?.addSymbolEffect(BounceSymbolEffect.bounce)
    }

    func setupEditMenu() {
        guard NSApp.mainMenu == nil else { return }

        let mainMenu = NSMenu()
        mainMenu.addItem(createAppMenuItem())
        mainMenu.addItem(createEditMenuItem())
        mainMenu.addItem(createWindowMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private func createAppMenuItem() -> NSMenuItem {
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About AppLocker", action: #selector(showAboutWindow), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide AppLocker", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit AppLocker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    private func createEditMenuItem() -> NSMenuItem {
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        return editMenuItem
    }

    private func createWindowMenuItem() -> NSMenuItem {
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenuItem.submenu = windowMenu
        return windowMenuItem
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.appearance = NSApp.appearance
        menu.removeAllItems()

        addHeaderMenuItems(to: menu)
        addPrimaryMenuItems(to: menu)
        addMaintenanceMenuItems(to: menu)
    }

    private func addHeaderMenuItems(to menu: NSMenu) {
        updateMenuBarIcon()

        let infoItem = NSMenuItem.sectionHeader(
            title: "AppLocker v\(Bundle.main.fullVersion)"
        )
        menu.addItem(infoItem)

        if AppUpdater.shared.hasAvailableUpdate, let ver = AppUpdater.shared.availableUpdateVersion {
            let updateNoticeItem = NSMenuItem(
                title: String(format: String(localized: "Version %@ available"), ver),
                action: #selector(checkForUpdates),
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
                action: #selector(openSystemSettingsForExtension),
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
        let manageItem = NSMenuItem(
            title: String(localized: "Manage the application list") + "…",
            action: #selector(openAppList),
            keyEquivalent: "l"
        )
        manageItem.keyEquivalentModifierMask = [.command, .shift]
        manageItem.image = NSImage(systemSymbolName: "lock.app.dashed", accessibilityDescription: nil)
        menu.addItem(manageItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: String(localized: "Settings") + "…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))

        menu.addItem(.separator())
    }

    private func addMaintenanceMenuItems(to menu: NSMenu) {
        let updateItem = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.image = NSImage(
            systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90",
            accessibilityDescription: nil
        )
        menu.addItem(updateItem)

        let aboutItem = NSMenuItem(
            title: String(localized: "About AppLocker"),
            action: #selector(showAboutWindow),
            keyEquivalent: ""
        )
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(
            title: String(localized: "Uninstall AppLocker") + "…",
            action: #selector(uninstall),
            keyEquivalent: ""
        )
        uninstallItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(uninstallItem)

        let resetItem = NSMenuItem(
            title: String(localized: "Reset AppLocker") + "…",
            action: #selector(resetApp),
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

extension Notification.Name {
    static let protectionStatusDidChange = Notification.Name("protectionStatusDidChange")
}
