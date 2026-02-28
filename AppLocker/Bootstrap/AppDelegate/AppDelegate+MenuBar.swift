//
//  AppDelegate+MenuBar.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import AppKit
import ServiceManagement

extension AppDelegate: NSMenuDelegate {
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "AppLocker")

            button.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22)
            ])
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let infoItem = NSMenuItem(title: "AppLocker v\(Bundle.main.fullVersion)",
                                action: nil,
                                keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(.separator())

        // MARK: - Primary Actions
        let manageItem = NSMenuItem(title: String(localized: "Manage the application list") + "…",
                                    action: #selector(openListApp),
                                    keyEquivalent: "l")
        manageItem.keyEquivalentModifierMask = [.command, .shift]
        manageItem.image = NSImage(systemSymbolName: "lock.app.dashed", accessibilityDescription: nil)
        menu.addItem(manageItem)

        menu.addItem(.separator())

        // MARK: - Settings & Preferences
        menu.addItem(NSMenuItem(title: String(localized: "Settings") + "…",
                                action: #selector(openSettings),
                                keyEquivalent: ","))

        if modeLock == .launcher {
            let launchItem = NSMenuItem(title: String(localized: "Launch At Login"),
                                        action: #selector(launchAtLogin),
                                        keyEquivalent: "")
            launchItem.target = self
            launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            menu.addItem(launchItem)
        }

        menu.addItem(.separator())

        // MARK: - Info & Updates
        let updateItem = NSMenuItem(title: String(localized: "Check for Updates…"),
                                action: #selector(checkUpdate),
                                keyEquivalent: "")
        updateItem.image = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90",
                                   accessibilityDescription: nil)
        menu.addItem(updateItem)

        let aboutItem = NSMenuItem(title: String(localized: "About AppLocker"),
                                action: #selector(about),
                                keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        // MARK: - Destructive Actions
        let uninstallItem = NSMenuItem(title: String(localized: "Uninstall AppLocker") + "…",
                                       action: #selector(uninstall),
                                       keyEquivalent: "")
        uninstallItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(uninstallItem)

        let resetItem = NSMenuItem(title: String(localized: "Reset AppLocker") + "…",
                                   action: #selector(resetApp),
                                   keyEquivalent: "")
        resetItem.image = NSImage(systemSymbolName: "arrow.counterclockwise.circle", accessibilityDescription: nil)
        resetItem.keyEquivalentModifierMask = [.option]
        resetItem.isAlternate = true
        menu.addItem(resetItem)

        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit AppLocker"),
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        #endif
    }
}
