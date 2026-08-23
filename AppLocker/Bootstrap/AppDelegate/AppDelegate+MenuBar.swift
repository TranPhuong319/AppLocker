//
//  AppDelegate+MenuBar.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit
import ServiceManagement

@MainActor
extension AppDelegate: NSMenuDelegate {
    func setupMenuBar() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }

        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "AppLocker")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.appearance = NSApp.appearance
        menu.delegate = self
        statusItem?.menu = menu
    }

    func setupEditMenu() {
        guard NSApp.mainMenu == nil else { return }

        let mainMenu = NSMenu()
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
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.appearance = NSApp.appearance
        menu.removeAllItems()

        addHeaderMenuItems(to: menu)
        addPrimaryMenuItems(to: menu)
        addMaintenanceMenuItems(to: menu)
    }

    private func addHeaderMenuItems(to menu: NSMenu) {
        let infoItem = NSMenuItem.sectionHeader(
            title: "AppLocker v\(Bundle.main.fullVersion)"
        )
        menu.addItem(infoItem)

        if !ExtensionInstaller.shared.isInstalled {
            let statusItem = NSMenuItem(
                title: String(localized: "System Extension Inactive"),
                action: #selector(openSystemSettingsForExtension),
                keyEquivalent: ""
            )
            menu.addItem(statusItem)
        }

        menu.addItem(.separator())
    }

    private func addPrimaryMenuItems(to menu: NSMenu) {
        let manageItem = NSMenuItem(
            title: String(localized: "Manage the application list") + "…",
            action: #selector(openListApp),
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
            action: #selector(checkUpdate),
            keyEquivalent: ""
        )
        updateItem.image = NSImage(
            systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90",
            accessibilityDescription: nil
        )
        menu.addItem(updateItem)

        let aboutItem = NSMenuItem(
            title: String(localized: "About AppLocker"),
            action: #selector(about),
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
