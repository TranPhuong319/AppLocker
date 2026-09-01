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
        registerOrUpdateItem(id: .mainButtonGroup) {
            TouchBarManager.buildMainButtonGroup(appState: appState)
        }
        registerOrUpdateItem(id: .addAppButtons) {
            TouchBarManager.buildAddAppTouchBarContent(appState: appState)
        }
        registerOrUpdateItem(id: .deleteQueueButtons) {
            TouchBarManager.buildDeleteQueueButtons(appState: appState)
        }
    }

    @objc private func handleWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.isVisible else { return }
        apply(to: window, type: appState.activeTouchBar)
    }

    private func observeActiveTouchBar() {
        withObservationTracking {
            let type = appState.activeTouchBar
            let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
            self.apply(to: targetWindow, type: type)
        } onChange: {
            Task { @MainActor [weak self] in
                self?.observeActiveTouchBar()
            }
        }
    }

    // NSTouchBarDelegate
    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard let viewBuilder = items[identifier] else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = viewBuilder()
        return item
    }

    // Register builder
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
            touchBar.principalItemIdentifier = .mainButtonGroup
            touchBar.defaultItemIdentifiers = [.mainButtonGroup]
        case .addAppPopup:
            touchBar.principalItemIdentifier = .addAppButtons
            touchBar.defaultItemIdentifiers = [
                .flexibleSpace,
                .addAppButtons,
                .flexibleSpace
            ]
        case .deleteQueuePopup:
            touchBar.principalItemIdentifier = .deleteQueueButtons
            touchBar.defaultItemIdentifiers = [
                .flexibleSpace,
                .deleteQueueButtons,
                .flexibleSpace
            ]
        }

        return touchBar
    }

    // MARK: - Static Builders (no capturing of self)
    private static func buildMainButtonGroup(appState: AppState) -> NSView {
        // plus button
        let plusButton = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add App")!,
            target: appState,
            action: #selector(AppState.openAddApp)
        )
        plusButton.isBordered = true

        // Otherwise return [red, plus]
        let redButton = buildDeleteQueueProminentButton()
        let stack = NSStackView(views: [redButton, plusButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        return stack
    }

    private static func buildAddAppTouchBarContent(appState: AppState) -> NSView {
        let otherButton = NSButton(
            title: String(localized: "Others…"),
            target: appState,
            action: #selector(AppState.chooseCustomApp)
        )
        otherButton.bezelStyle = .rounded
        let width = otherButton.intrinsicContentSize.width + 80
        otherButton.widthAnchor
            .constraint(equalToConstant: width)
            .isActive = true

        let closeButton = NSButton(
            title: String(localized: "Close"),
            target: appState,
            action: #selector(AppState.dismissAddAppSheet)
        )
        closeButton.isBordered = true
        closeButton.bezelStyle = .rounded

        let lockButton = LockTouchBarButton(
            title: String(localized: "Lock"),
            target: appState,
            action: #selector(AppState.lockSelectedApps)
        )
        lockButton.isBordered = true
        lockButton.bezelStyle = .rounded
        lockButton.keyEquivalent = "\r"

        let centerStack = NSStackView(views: [closeButton, lockButton])
        centerStack.orientation = .horizontal
        centerStack.spacing = 6
        centerStack.alignment = .centerY

        // Main group: [Other] ... 50pt ... [Close | Lock]
        let mainStack = NSStackView(views: [otherButton, centerStack])
        mainStack.orientation = .horizontal
        mainStack.spacing = 50
        mainStack.alignment = .centerY

        NSLayoutConstraint.activate([
            lockButton.widthAnchor.constraint(equalTo: otherButton.widthAnchor),
            closeButton.widthAnchor.constraint(equalTo: otherButton.widthAnchor)
        ])

        return mainStack
    }

    private static func buildDeleteQueueButtons(appState: AppState) -> NSView {
        let unlockButton = NSButton(
            title: String(localized: "Unlock"),
            target: appState,
            action: #selector(AppState.unlockQueuedApps)
        )
        unlockButton.isBordered = true
        unlockButton.bezelStyle = .rounded
        unlockButton.keyEquivalent = "\r"

        let clearButton = NSButton(
            title: String(localized: "Cancel"),
            target: appState,
            action: #selector(AppState.clearDeleteQueue)
        )
        clearButton.isBordered = true
        clearButton.bezelStyle = .rounded

        let width = max(unlockButton.intrinsicContentSize.width, clearButton.intrinsicContentSize.width) + 80
        clearButton.widthAnchor
            .constraint(equalToConstant: width)
            .isActive = true

        let stack = NSStackView(views: [clearButton, unlockButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY

        NSLayoutConstraint.activate([
            unlockButton.widthAnchor.constraint(equalTo: clearButton.widthAnchor)
        ])

        return stack
    }

    // Prominent red button builder kept static so main builder doesn't capture self
    private static func buildDeleteQueueProminentButton() -> NSView {
        let container = NSView()
        let button = DeleteQueueTouchBarButton(
            title: "",
            target: AppState.shared,
            action: #selector(AppState.showDeleteQueueSheet)
        )

        button.isBordered = false
        button.contentTintColor = NSColor.white
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.systemRed.cgColor
        button.layer?.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            button.heightAnchor.constraint(equalToConstant: 30)
        ])

        return container
    }
}

// MARK: - Self-Updating TouchBar Components

@MainActor
class DeleteQueueTouchBarButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupObservation()
    }

    private func setupObservation() {
        // Only update title; visibility handled by TouchBarManager layout.
        withObservationTracking {
            let queue = AppState.shared.deleteQueue
            self.isHidden = queue.isEmpty
            self.title = String(
                localized: "Waiting to unlock \(queue.count) application(s)..."
            )
        } onChange: {
            Task { @MainActor [weak self] in
                self?.setupObservation()
            }
        }
    }
}

@MainActor
class LockTouchBarButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupObservation()
    }

    private func setupObservation() {
        withObservationTracking {
            let selected = AppState.shared.selectedToLock
            let isLocking = AppState.shared.isLocking
            self.title = String(localized: "Lock")
            self.isEnabled = !selected.isEmpty && !isLocking
        } onChange: {
            Task { @MainActor [weak self] in
                self?.setupObservation()
            }
        }
    }
}

extension NSTouchBarItem.Identifier {
    static let addAppButtons = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.addAppButtons"
    )
    static let deleteQueueButtons = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.deleteQueueButtons"
    )
    static let mainButtonGroup = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.mainButtonGroup"
    )
}
