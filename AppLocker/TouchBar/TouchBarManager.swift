//
//  TouchBarManager.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//
//  EN: Manages NSTouchBar items and updates with AppState changes.
//  VI: Quản lý các mục NSTouchBar và cập nhật theo thay đổi của AppState.
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
    }

    private func refreshDeleteQueueButton() {
        guard let button = self.deleteQueueButton else { return }
        button.isHidden = self.appState.deleteQueue.isEmpty
        button.title = "Waiting to unlock %d application(s)...".localized(with: self.appState.deleteQueue.count)
    }

    private func refreshLockButton() {
        guard let window = NSApp.keyWindow,
              let touchBar = window.touchBar,
              let item = touchBar.item(forIdentifier: .lockButton) as? NSCustomTouchBarItem,
              let button = item.view as? NSButton else { return }

        button.title = "Lock (%d)".localized(with: self.appState.selectedToLock.count)
        button.isEnabled = !appState.selectedToLock.isEmpty && !appState.isLocking
    }

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
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
        registerOrUpdateItem(id: .addApp) {
            let symbolImage = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add App")
            let button = NSButton(
                image: symbolImage!,
                target: TouchBarActionProxy.shared,
                action: #selector(TouchBarActionProxy.shared.openPopupAddApp)
            )
            button.isBordered = true
            return button
        }

        registerOrUpdateItem(id: .showDeleteQueuePopup) { [weak self] in
            guard let self = self else { return NSView() }
            return self.createDeleteQueueProminentButton()
        }

        touchBar.defaultItemIdentifiers = [.flexibleSpace, .showDeleteQueuePopup, .addApp]
    }

    private func configureAddAppPopupTouchBar(_ touchBar: NSTouchBar) {
        registerOrUpdateItem(id: .addAppOther) {
            NSButton(title: "Others…".localized,
                     target: TouchBarActionProxy.shared,
                     action: #selector(TouchBarActionProxy.shared.addAnotherApp))
        }

        registerOrUpdateItem(id: .closeAddPopupApp) {
            let button = NSButton(title: "Close".localized,
                                  target: TouchBarActionProxy.shared,
                                  action: #selector(TouchBarActionProxy.shared.closeAddAppPopup))
            button.bezelStyle = .rounded
            return button
        }

        registerOrUpdateItem(id: .lockButton) { [weak self] in
            guard let self = self else { return NSView() }
            let button = NSButton(title: "Lock (%d)".localized(with: self.appState.selectedToLock.count),
                                  target: TouchBarActionProxy.shared,
                                  action: #selector(TouchBarActionProxy.shared.lockApp))
            button.bezelStyle = .rounded
            button.keyEquivalent = "\r"
            button.isEnabled = !self.appState.selectedToLock.isEmpty && !self.appState.isLocking
            return button
        }

        touchBar.defaultItemIdentifiers = [.addAppOther, .flexibleSpace, .closeAddPopupApp, .lockButton]
    }

    private func configureDeleteQueuePopupTouchBar(_ touchBar: NSTouchBar) {
        registerOrUpdateItem(id: .deleteQueueButtons) {
            let unlockButton = NSButton(title: "Unlock".localized,
                                        target: TouchBarActionProxy.shared,
                                        action: #selector(TouchBarActionProxy.shared.unlockApp))
            unlockButton.isBordered = true
            unlockButton.bezelStyle = .rounded
            unlockButton.keyEquivalent = "\r"

            let clearButton = NSButton(title: "Delete all from the waiting list".localized,
                                       target: TouchBarActionProxy.shared,
                                       action: #selector(TouchBarActionProxy.shared.clearWaitingList))
            clearButton.isBordered = true
            clearButton.bezelStyle = .rounded

            let stack = NSStackView(views: [clearButton, unlockButton])
            stack.orientation = .horizontal
            stack.spacing = 10
            stack.alignment = .centerY
            return stack
        }

        touchBar.defaultItemIdentifiers = [.flexibleSpace, .deleteQueueButtons]
    }

    // MARK: - UI Component Factories
    private func createDeleteQueueProminentButton() -> NSView {
        let container = NSView()
        let button = NSButton(
            title: "Waiting to unlock %d application(s)...".localized(with: self.appState.deleteQueue.count),
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

        self.deleteQueueButton = button
        button.isHidden = self.appState.deleteQueue.isEmpty
        return container
    }}

extension NSTouchBarItem.Identifier {
    static let addApp = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.addApp")
    static let lockButton = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.lockButton")
    static let closeAddPopupApp = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.closeAddPopupApp"
    )
    static let addAppOther = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.addAppOther")
    static let centerButtonsLock = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.centerButtonsLock"
    )
    static let unlockButton = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.unlockButton"
    )
    static let clearWaitList = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.clearWaitList"
    )
    static let deleteQueueButtons = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.deleteQueueButtons"
    )
    static let showDeleteQueuePopup = NSTouchBarItem.Identifier(
        "com.TranPhuong319.AppLocker.showDeleteQueuePopup"
    )
}
