//
//  TouchBarManager.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//

import AppKit

@MainActor
final class TouchBarManager: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarManager()

    private let appState = AppState.shared
    private weak var targetWindow: NSWindow?
    private var isObservingState = false

    func attach(to window: NSWindow) {
        if targetWindow !== window {
            if let oldWindow = targetWindow {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.willBeginSheetNotification,
                    object: oldWindow
                )
            }
            targetWindow = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWillBeginSheet(_:)),
                name: NSWindow.willBeginSheetNotification,
                object: window
            )
        }

        if !isObservingState {
            isObservingState = true
            observeOnMainActor(owner: self) { manager in
                manager.applyCurrentTouchBar()
            }
        } else {
            applyCurrentTouchBar()
        }
    }

    @objc private func handleWillBeginSheet(_ notification: Notification) {
        guard let sheetWindow = notification.userInfo?["NSWindow"] as? NSWindow else { return }
        sheetWindow.touchBar = makeTouchBar(for: appState.activeTouchBar)
    }

    private func applyCurrentTouchBar() {
        let type = appState.activeTouchBar
        _ = appState.confirmedMissingApps.isEmpty
        _ = appState.deleteQueue.isEmpty

        guard let targetWindow, targetWindow.isVisible else { return }
        let touchBar = makeTouchBar(for: type)
        targetWindow.touchBar = touchBar
        targetWindow.attachedSheet?.touchBar = touchBar
    }

    // MARK: - NSTouchBarDelegate

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        switch identifier {
        case .searchItem:
            return SearchTouchBarItem(identifier: identifier)
        case .addAppItem:
            return NSButtonTouchBarItem(
                identifier: identifier,
                image: NSImage(
                    systemSymbolName: "plus",
                    accessibilityDescription: String(localized: "Add App")
                ) ?? NSImage(),
                target: appState,
                action: #selector(AppState.openAddApp)
            )
        case .missingAppsItem:
            return makeMissingAppsItem(identifier: identifier)
        case .deleteQueueItem:
            return makeDeleteQueueItem(identifier: identifier)
        case .addAppButtons:
            return makeAddAppGroup(identifier: identifier)
        case .deleteQueueButtons:
            return makeDeleteQueueGroup(identifier: identifier)
        case .missingAppsButtons:
            return makeMissingAppsGroup(identifier: identifier)
        default:
            return nil
        }
    }

    private func makeDeleteQueueGroup(identifier: NSTouchBarItem.Identifier) -> NSGroupTouchBarItem {
        makeGroupItem(identifier: identifier, items: [
            makeButtonItem(
                idSuffix: "deleteQueueCancel",
                title: String(localized: "Cancel"),
                action: #selector(AppState.clearDeleteQueue),
                width: 180
            ),
            makeButtonItem(
                idSuffix: "deleteQueueUnlock",
                title: String(localized: "Unlock"),
                action: #selector(AppState.unlockQueuedApps),
                bezelColor: .controlAccentColor,
                width: 180
            )
        ])
    }

    private func makeMissingAppsGroup(identifier: NSTouchBarItem.Identifier) -> NSGroupTouchBarItem {
        makeGroupItem(identifier: identifier, splitLeading: true, items: [
            makeButtonItem(
                idSuffix: "missingAppsCancel",
                title: String(localized: "Cancel"),
                action: #selector(AppState.closeMissingApps)
            ),
            makeButtonItem(
                idSuffix: "missingAppsHide",
                title: String(localized: "Hide"),
                action: #selector(AppState.hideAllMissingApps)
            ),
            makeButtonItem(
                idSuffix: "missingAppsRemove",
                title: String(localized: "Remove"),
                action: #selector(AppState.removeAllMissingApps),
                bezelColor: .controlAccentColor
            )
        ])
    }

    private func makeMissingAppsItem(identifier: NSTouchBarItem.Identifier) -> NSButtonTouchBarItem {
        let item = NSButtonTouchBarItem(
            identifier: identifier,
            title: "\(appState.confirmedMissingApps.count)",
            target: appState,
            action: #selector(AppState.openMissingApps)
        )
        item.image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: String(localized: "Review missing applications")
        )
        item.bezelColor = .systemOrange
        observeOnMainActor(owner: item) { barItem in
            barItem.title = "\(AppState.shared.confirmedMissingApps.count)"
        }
        return item
    }

    private func makeDeleteQueueItem(identifier: NSTouchBarItem.Identifier) -> NSButtonTouchBarItem {
        let item = NSButtonTouchBarItem(
            identifier: identifier,
            title: "",
            target: appState,
            action: #selector(AppState.showDeleteQueueSheet)
        )
        item.bezelColor = .systemRed
        observeOnMainActor(owner: item) { barItem in
            let count = AppState.shared.deleteQueue.count
            barItem.title = String(localized: "Waiting to unlock \(count) application(s)...")
        }
        return item
    }

    private func makeAddAppGroup(identifier: NSTouchBarItem.Identifier) -> NSGroupTouchBarItem {
        let lockItem = makeButtonItem(
            idSuffix: "addAppLock",
            title: String(localized: "Lock"),
            action: #selector(AppState.lockSelectedApps),
            bezelColor: .controlAccentColor
        )
        observeOnMainActor(owner: lockItem) { barItem in
            barItem.isEnabled = !AppState.shared.selectedToLock.isEmpty && !AppState.shared.isLocking
        }
        return makeGroupItem(identifier: identifier, splitLeading: true, items: [
            makeButtonItem(
                idSuffix: "addAppOther",
                title: String(localized: "Others…"),
                action: #selector(AppState.chooseCustomApp)
            ),
            makeButtonItem(
                idSuffix: "addAppClose",
                title: String(localized: "Close"),
                action: #selector(AppState.dismissAddAppSheet)
            ),
            lockItem
        ])
    }

    private func makeTouchBar(for type: AppState.TouchBarType) -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self

        switch type {
        case .mainWindow:
            var identifiers: [NSTouchBarItem.Identifier] = [.searchItem, .flexibleSpace]
            if appState.deleteQueue.isEmpty {
                touchBar.principalItemIdentifier = .addAppItem
                identifiers.append(.addAppItem)
                identifiers.append(.flexibleSpace)
                if !appState.confirmedMissingApps.isEmpty {
                    identifiers.append(.missingAppsItem)
                }
            } else {
                touchBar.principalItemIdentifier = .deleteQueueItem
                identifiers.append(.deleteQueueItem)
                identifiers.append(.flexibleSpace)
                identifiers.append(.addAppItem)
                if !appState.confirmedMissingApps.isEmpty {
                    identifiers.append(.missingAppsItem)
                }
            }
            identifiers.append(.fixedSpaceLarge)
            touchBar.defaultItemIdentifiers = identifiers
        case .addAppPopup:
            touchBar.principalItemIdentifier = .addAppButtons
            touchBar.defaultItemIdentifiers = [.flexibleSpace, .addAppButtons, .flexibleSpace]
        case .deleteQueuePopup:
            touchBar.principalItemIdentifier = .deleteQueueButtons
            touchBar.defaultItemIdentifiers = [.flexibleSpace, .deleteQueueButtons, .flexibleSpace]
        case .missingAppsPopup:
            touchBar.principalItemIdentifier = .missingAppsButtons
            touchBar.defaultItemIdentifiers = [.flexibleSpace, .missingAppsButtons, .flexibleSpace]
        }
        return touchBar
    }

    private func makeGroupItem(
        identifier: NSTouchBarItem.Identifier,
        splitLeading: Bool = false,
        items: [NSTouchBarItem]
    ) -> NSGroupTouchBarItem {
        let group = NSGroupTouchBarItem(identifier: identifier, items: items)
        if splitLeading, let first = items.first {
            group.groupTouchBar.defaultItemIdentifiers = [first.identifier, .fixedSpaceLarge]
                + items.dropFirst().map(\.identifier)
        }
        return group
    }

    private func makeButtonItem(
        idSuffix: String,
        title: String,
        action: Selector,
        bezelColor: NSColor? = nil,
        width: CGFloat = 140
    ) -> NSButtonTouchBarItem {
        let item = NSButtonTouchBarItem(
            identifier: NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.\(idSuffix)"),
            title: title,
            target: appState,
            action: action
        )
        item.bezelColor = bezelColor
        item.view?.widthAnchor.constraint(equalToConstant: width).isActive = true
        return item
    }
}
