//
//  TouchBarManager.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//

import AppKit
import Observation

@MainActor
class TouchBarManager: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarManager()
    let appState = AppState.shared
    private var items: [NSTouchBarItem.Identifier: () -> NSView] = [:]

    override init() {
        super.init()
        registerDefaultBuilders()
        observeActiveTouchBar()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func registerDefaultBuilders() {
        let appState = self.appState
        registerOrUpdateItem(id: .deleteQueueItem) { TouchBarManager.buildDeleteQueueProminentButton() }
        registerOrUpdateItem(id: .addAppButtons) { TouchBarManager.buildAddAppTouchBarContent(appState: appState) }
        registerOrUpdateItem(id: .deleteQueueButtons) { TouchBarManager.buildDeleteQueueButtons(appState: appState) }
        registerOrUpdateItem(id: .missingAppsButtons) {
            TouchBarManager.buildMissingAppsTouchBarContent(appState: appState)
        }
    }

    @objc private func handleWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.isVisible else { return }
        apply(to: window, type: appState.activeTouchBar)
    }

    private func observeActiveTouchBar() {
        withObservationTracking {
            let type = appState.activeTouchBar
            let hasMissing = !appState.confirmedMissingApps.isEmpty
            _ = hasMissing
            let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
            self.apply(to: targetWindow, type: type)
        } onChange: {
            Task { @MainActor [weak self] in self?.observeActiveTouchBar() }
        }
    }

    // MARK: - NSTouchBarDelegate

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        if identifier == .searchItem {
            return SearchTouchBarItem(identifier: identifier)
        }
        if identifier == .addAppItem {
            return NSButtonTouchBarItem(
                identifier: identifier,
                image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add App")!,
                target: appState,
                action: #selector(AppState.openAddApp)
            )
        }
        if identifier == .missingAppsItem {
            return MissingAppsTouchBarItem(identifier: identifier)
        }
        guard let viewBuilder = items[identifier] else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = viewBuilder()
        return item
    }

    func registerOrUpdateItem(id: NSTouchBarItem.Identifier, builder: @escaping () -> NSView) {
        items[id] = builder
    }

    func apply(to window: NSWindow?, type: AppState.TouchBarType) {
        guard let window else { return }
        window.touchBar = makeTouchBar(for: type)
    }

    func makeTouchBar(for type: AppState.TouchBarType) -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self

        switch type {
        case .mainWindow:
            touchBar.principalItemIdentifier = .deleteQueueItem
            var identifiers: [NSTouchBarItem.Identifier] = [
                .searchItem, .flexibleSpace, .deleteQueueItem, .flexibleSpace
            ]
            if !appState.confirmedMissingApps.isEmpty {
                identifiers.append(.missingAppsItem)
            }
            identifiers.append(.addAppItem)
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
}
