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
    var appState = AppState.shared
    private var cancellables = Set<AnyCancellable>()
    private var deleteQueueButton: NSButton?

    private var items: [NSTouchBarItem.Identifier: () -> NSView] = [:]

    override init() {
        super.init()
        appState.$deleteQueue
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshDeleteQueueButton()
            }
            .store(in: &cancellables)

        appState.$selectedToLock
            .combineLatest(appState.$isLocking)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.refreshLockButton()
            }
            .store(in: &cancellables)

        appState.$activeTouchBar
            .receive(on: RunLoop.main)
            .sink { [weak self] type in
                self?.apply(to: NSApp.keyWindow, type: type)
            }
            .store(in: &cancellables)
    }

    private func refreshDeleteQueueButton() {
        guard let button = self.deleteQueueButton else { return }
        button.isHidden = self.appState.deleteQueue.isEmpty
        button.title = String(
            localized: "Waiting to unlock \(appState.deleteQueue.count) application(s)..."
        )
    }

    private func refreshLockButton() {
        guard let window = NSApp.keyWindow,
            let touchBar = window.touchBar,
            let item = touchBar.item(forIdentifier: .centerButtonsLock) as? NSCustomTouchBarItem,
            let stack = item.view as? NSStackView
        else { return }

        // tìm nút lock theo tag
        if let lockButton = stack.subviews.first(where: { $0.tag == 100 }) as? NSButton {
            lockButton.title = String(localized: "Lock (\(appState.selectedToLock.count))")
            lockButton.isEnabled = !appState.selectedToLock.isEmpty && !appState.isLocking
        }
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard let viewBuilder = items[identifier] else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = viewBuilder()
        return item
    }

    func clear() {
        items.removeAll()
    }

    func registerOrUpdateItem(id: NSTouchBarItem.Identifier, builder: @escaping () -> NSView) {
        items[id] = builder
    }

    func apply(to window: NSWindow?, type: AppState.TouchBarType) {
        guard let window else { return }
        window.touchBar = makeTouchBar(for: type)
    }

    func makeTouchBar(for type: AppState.TouchBarType) -> NSTouchBar {
        clear()

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

    // MARK: - Private Configuration Helpers
    private func configureMainWindowTouchBar(_ touchBar: NSTouchBar) {
        registerOrUpdateItem(id: .mainButtonGroup) { [weak self] in
            guard let self else { return NSView() }

            let redButton = self.createDeleteQueueProminentButton()

            let plusButton = NSButton(
                image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add App")!,
                target: TouchBarActionProxy.shared,
                action: #selector(TouchBarActionProxy.shared.openPopupAddApp)
            )
            plusButton.isBordered = true

            let stack = NSStackView(views: [redButton, plusButton])
            stack.orientation = .horizontal
            stack.spacing = 10
            stack.alignment = .centerY
            return stack
        }

        touchBar.principalItemIdentifier = .mainButtonGroup
        touchBar.defaultItemIdentifiers = [
            .mainButtonGroup
        ]

    }

    private func configureAddAppPopupTouchBar(_ touchBar: NSTouchBar) {
        registerOrUpdateItem(id: .addAppOther) {
            NSButton(
                title: String(localized: "Others…"),
                target: TouchBarActionProxy.shared,
                action: #selector(TouchBarActionProxy.shared.addAnotherApp))
        }

        registerOrUpdateItem(id: .centerButtonsLock) { [weak self] in
            guard let self = self else { return NSView() }

            let lockButton = NSButton(
                title: String(localized: "Lock (\(appState.selectedToLock.count))"),
                target: TouchBarActionProxy.shared,
                action: #selector(TouchBarActionProxy.shared.lockApp)
            )
            lockButton.bezelStyle = .rounded
            lockButton.keyEquivalent = "\r"
            lockButton.isEnabled = !self.appState.selectedToLock.isEmpty && !self.appState.isLocking
            lockButton.tag = 100

            let closeButton = NSButton(
                title: String(localized: "Close"),
                target: TouchBarActionProxy.shared,
                action: #selector(TouchBarActionProxy.shared.closeAddAppPopup)
            )
            closeButton.bezelStyle = .rounded
            closeButton.tag = 101

            let stack = NSStackView(views: [closeButton, lockButton])
            stack.orientation = .horizontal
            stack.spacing = 12
            stack.alignment = .centerY
            stack.translatesAutoresizingMaskIntoConstraints = false
            return stack
        }

        // Đặt principalItemIdentifier để hệ thống căn giữa item này trong vùng nội dung
        touchBar.principalItemIdentifier = .centerButtonsLock

        // Layout: Others bên trái, 1 khoảng fixed nhỏ, sau đó phần nội dung còn lại (center item sẽ nằm giữa phần nội dung)
        touchBar.defaultItemIdentifiers = [
            .addAppOther,
            .flexibleSpace,
            .centerButtonsLock,
            .flexibleSpace,
        ]
    }

    private func configureDeleteQueuePopupTouchBar(_ touchBar: NSTouchBar) {
        registerOrUpdateItem(id: .deleteQueueButtons) {
            let unlockButton = NSButton(
                title: String(localized: "Unlock"),
                target: TouchBarActionProxy.shared,
                action: #selector(TouchBarActionProxy.shared.unlockApp))
            unlockButton.isBordered = true
            unlockButton.bezelStyle = .rounded
            unlockButton.keyEquivalent = "\r"

            let clearButton = NSButton(
                title:
                    String(localized: "Delete all from the waiting list"),
                target: TouchBarActionProxy.shared,
                action: #selector(TouchBarActionProxy.shared.clearWaitingList))
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

        touchBar.principalItemIdentifier = .deleteQueueButtons
        touchBar.defaultItemIdentifiers = [
            .flexibleSpace,
            .deleteQueueButtons,
            .flexibleSpace,
        ]
    }

    // MARK: - UI Component Factories
    private func createDeleteQueueProminentButton() -> NSView {
        let container = NSView()
        let button = NSButton(
            title: String(
                localized: "Waiting to unlock \(appState.deleteQueue.count) application(s)..."
            ),
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
            button.heightAnchor.constraint(equalToConstant: 30),
        ])

        self.deleteQueueButton = button
        button.isHidden = self.appState.deleteQueue.isEmpty
        return container
    }
}

extension NSTouchBarItem.Identifier {
    static let addAppOther = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.addAppOther"
    )
    static let centerButtonsLock = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.centerButtonsLock"
    )
    static let deleteQueueButtons = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.deleteQueueButtons"
    )
    static let mainButtonGroup = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.mainButtonGroup"
    )
}
