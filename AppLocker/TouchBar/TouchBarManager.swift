//
//  TouchBarManager.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//

import AppKit
import Combine

class TouchBarManager: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarManager()
    let appState = AppState.shared
    private var cancellables = Set<AnyCancellable>()

    private var items: [NSTouchBarItem.Identifier: () -> NSView] = [:]

    override init() {
        super.init()

        // When activeTouchBar changes -> apply corresponding touchBar
        appState.$activeTouchBar
            .receive(on: RunLoop.main)
            .sink { [weak self] type in
                guard let self = self else { return }
                let windows = NSApp.windows.filter { $0.isVisible }
                for window in windows {
                    self.apply(to: window, type: type)
                }
            }
            .store(in: &cancellables)
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
        items.removeAll()

        let touchBar = NSTouchBar()
        touchBar.delegate = self

        switch type {
        case .mainWindow:
            configureMainWindowTouchBar(touchBar)
        case .addAppPopup:
            configureAddAppPopupTouchBar(touchBar)
        case .deleteQueuePopup:
            configureDeleteQueuePopupTouchBar(touchBar)
        }

        return touchBar
    }

    // MARK: - Configuration (register builders that DON'T capture self)
    private func configureMainWindowTouchBar(_ touchBar: NSTouchBar) {
        // capture appState locally (singleton) — closure does not capture self
        let appState = self.appState
        registerOrUpdateItem(id: .mainButtonGroup) {
            return TouchBarManager.buildMainButtonGroup(appState: appState)
        }

        touchBar.principalItemIdentifier = .mainButtonGroup
        touchBar.defaultItemIdentifiers = [.mainButtonGroup]
    }

    private func configureAddAppPopupTouchBar(_ touchBar: NSTouchBar) {
        let appState = self.appState

        registerOrUpdateItem(id: .addAppButtons) {
            return TouchBarManager.buildAddAppTouchBarContent(appState: appState)
        }

        touchBar.principalItemIdentifier = .addAppButtons
        touchBar.defaultItemIdentifiers = [
            .flexibleSpace,
            .addAppButtons,
            .flexibleSpace
        ]
    }

    private func configureDeleteQueuePopupTouchBar(_ touchBar: NSTouchBar) {
        let appState = self.appState

        registerOrUpdateItem(id: .deleteQueueButtons) {
            return TouchBarManager.buildDeleteQueueButtons(appState: appState)
        }

        touchBar.principalItemIdentifier = .deleteQueueButtons
        touchBar.defaultItemIdentifiers = [
            .flexibleSpace,
            .deleteQueueButtons,
            .flexibleSpace
        ]
    }

    // MARK: - Static Builders (no capturing of self)
    private static func buildMainButtonGroup(appState: AppState) -> NSView {
        // plus button
        let plusButton = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add App")!,
            target: TouchBarActionProxy.shared,
            action: #selector(TouchBarActionProxy.shared.openPopupAddApp)
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
            target: TouchBarActionProxy.shared,
            action: #selector(TouchBarActionProxy.shared.addAnotherApp)
        )
        otherButton.bezelStyle = .rounded
        let width = otherButton.intrinsicContentSize.width + 80
        otherButton.widthAnchor
            .constraint(equalToConstant: width)
            .isActive = true

        let closeButton = NSButton(
            title: String(localized: "Close"),
            target: TouchBarActionProxy.shared,
            action: #selector(TouchBarActionProxy.shared.closeAddAppPopup)
        )
        closeButton.isBordered = true
        closeButton.bezelStyle = .rounded

        let lockButton = LockTouchBarButton(
            title: String(localized: "Lock"),
            target: TouchBarActionProxy.shared,
            action: #selector(TouchBarActionProxy.shared.lockApp)
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
            target: TouchBarActionProxy.shared,
            action: #selector(TouchBarActionProxy.shared.unlockApp)
        )
        unlockButton.isBordered = true
        unlockButton.bezelStyle = .rounded
        unlockButton.keyEquivalent = "\r"

        let clearButton = NSButton(
            title: String(localized: "Delete all from the waiting list"),
            target: TouchBarActionProxy.shared,
            action: #selector(TouchBarActionProxy.shared.clearWaitingList)
        )
        clearButton.isBordered = true
        clearButton.bezelStyle = .rounded

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
            target: TouchBarActionProxy.shared,
            action: #selector(TouchBarActionProxy.shared.showDeleteQueuePopup)
        )

        button.isBordered = false
        button.contentTintColor = .white
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

class DeleteQueueTouchBarButton: NSButton {
    private var cancellables = Set<AnyCancellable>()

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
        AppState.shared.$deleteQueue
            .receive(on: RunLoop.main)
            .sink { [weak self] queue in
                self?.isHidden = queue.isEmpty
                self?.title = String(
                    localized: "Waiting to unlock \(queue.count) application(s)..."
                )
            }
            .store(in: &cancellables)
    }
}

class LockTouchBarButton: NSButton {
    private var cancellables = Set<AnyCancellable>()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupObservation()
    }

    private func setupObservation() {
        AppState.shared.$selectedToLock
            .combineLatest(AppState.shared.$isLocking)
            .receive(on: RunLoop.main)
            .sink { [weak self] selected, isLocking in
                self?.title = String(localized: "Lock")
                self?.isEnabled = !selected.isEmpty && !isLocking
            }
            .store(in: &cancellables)
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
