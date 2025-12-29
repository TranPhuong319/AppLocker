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

        if NSEvent.modifierFlags.contains(.option) {
            buildOptionMenu(for: menu)
        } else {
            buildNormalMenu(for: menu)
        }
    }

    private func buildNormalMenu(for menu: NSMenu) {
        let manageItem = NSMenuItem(title: "Manage the application list".localized,
                                    action: #selector(openListApp),
                                    keyEquivalent: "l")
        manageItem.keyEquivalentModifierMask = [.command, .shift]
        manageItem.image = NSImage(systemSymbolName: "lock.app.dashed", accessibilityDescription: nil)
        menu.addItem(manageItem)

        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AppLocker".localized,
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        #endif
    }

    private func buildOptionMenu(for menu: NSMenu) {
        menu.addItem(NSMenuItem(title: "Settings".localized,
                                action: #selector(openSettings),
                                keyEquivalent: ","))
        menu.addItem(.separator())

        if modeLock == .launcher {
            let launchItem = NSMenuItem(title: "Launch At Login".localized,
                                        action: #selector(launchAtLogin),
                                        keyEquivalent: "")
            launchItem.target = self
            launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            menu.addItem(launchItem)
        }

        let updateItem = NSMenuItem(title: "Check for Updates...".localized,
                                action: #selector(checkUpdate),
                                keyEquivalent: "")
        updateItem.image = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90",
                                   accessibilityDescription: nil)
        menu.addItem(updateItem)
        let aboutItem = NSMenuItem(title: "About AppLocker".localized,
                                action: #selector(about),
                                keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(title: "Uninstall AppLocker".localized,
                                       action: #selector(uninstall),
                                       keyEquivalent: "")
        uninstallItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(uninstallItem)

        let resetItem = NSMenuItem(title: "Reset AppLocker".localized,
                                   action: #selector(resetApp),
                                   keyEquivalent: "")
        resetItem.image = NSImage(systemSymbolName: "arrow.counterclockwise.circle", accessibilityDescription: nil)

        // EN: Alternate item (Option+Shift) to replace Uninstall.
        // VI: Mục thay thế (Option+Shift) để thay thế Uninstall.
        resetItem.keyEquivalentModifierMask = NSEvent.ModifierFlags([.option, .shift])
        resetItem.isAlternate = true

        menu.addItem(resetItem)
    }
}
