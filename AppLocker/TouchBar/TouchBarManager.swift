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

        // Lắng nghe thay đổi selectedToLock để update Lock button
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
              let tb = window.touchBar,
              let item = tb.item(forIdentifier: .lockButton) as? NSCustomTouchBarItem,
              let button = item.view as? NSButton else { return }

        button.title = "Lock (%d)".localized(with: self.appState.selectedToLock.count)
        button.isEnabled = !appState.selectedToLock.isEmpty && !appState.isLocking
    }
    
    func makeTouchBar(for type: AppState.TouchBarType) -> NSTouchBar {
        clear()

        let tb = NSTouchBar()
        tb.delegate = self

        switch type {
        case .mainWindow:
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
            
            registerOrUpdateItem(id: .showDeleteQueuePopup) {
                // Container view full width
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
                
                // Chiều cao cố định
                button.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(button)
                
                // Constraints để nút stretch full width
                NSLayoutConstraint.activate([
                    button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
                    button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 0),
                    button.topAnchor.constraint(equalTo: container.topAnchor),
                    button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    button.heightAnchor.constraint(equalToConstant: 30) // chiều cao
                ])
                
                self.deleteQueueButton = button
                button.isHidden = self.appState.deleteQueue.isEmpty
                
                return container
            }

            tb.defaultItemIdentifiers = [
                .flexibleSpace,
                .showDeleteQueuePopup,
                .addApp,
            ]
            
        case .addAppPopup:
            registerOrUpdateItem(id: .addAppOther) {
                let button = NSButton(title: "Others…".localized,
                                      target: TouchBarActionProxy.shared,
                                      action: #selector(TouchBarActionProxy.shared.addAnotherApp))
                return button
            }
            registerOrUpdateItem(id: .closeAddPopupApp) {
                let button = NSButton(title: "Close".localized,
                                      target: TouchBarActionProxy.shared,
                                      action: #selector(TouchBarActionProxy.shared.closeAddAppPopup))
                button.bezelStyle = .rounded
                return button
            }
            registerOrUpdateItem(id: .lockButton) {
                let button = NSButton(title: "Lock (%d)".localized(with: self.appState.selectedToLock.count),
                                      target: TouchBarActionProxy.shared,
                                      action: #selector(TouchBarActionProxy.shared.lockApp))
                button.bezelStyle = .rounded
                button.keyEquivalent = "\r"
                button.isEnabled = !self.appState.selectedToLock.isEmpty && !self.appState.isLocking
                return button
            }
            tb.defaultItemIdentifiers = [
                .addAppOther,
                .flexibleSpace,
                .closeAddPopupApp,
                .lockButton,
            ]
            
        case .deleteQueuePopup:
            registerOrUpdateItem(id: .deleteQueueButtons) {
                let unlockButton = NSButton(title: "Unlock".localized, target: TouchBarActionProxy.shared,
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
            
            tb.defaultItemIdentifiers = [
                .flexibleSpace,
                .deleteQueueButtons,
            ]
        }

        return tb
    }

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let viewBuilder = items[identifier] else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = viewBuilder()
        return item
    }

    /// Xóa hết item cũ
    func clear() {
        items.removeAll()
    }

    /// Đăng ký hoặc update item
    func registerOrUpdateItem(id: NSTouchBarItem.Identifier, builder: @escaping () -> NSView) {
        items[id] = builder
    }

    /// Apply touchbar cho 1 window với loại cụ thể
    func apply(to window: NSWindow?, type: AppState.TouchBarType) {
        guard let window else { return }
        window.touchBar = makeTouchBar(for: type)
    }
}

// Định nghĩa identifier chung
extension NSTouchBarItem.Identifier {
    // Main Window
    static let addApp = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.addApp")
    // Popup Add Lock App
    static let lockButton = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.lockButton")
    static let closeAddPopupApp = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.closeAddPopupApp")
    static let addAppOther = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.addAppOther")
    static let centerButtonsLock = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.centerButtonsLock")
    // Popup Unlock App
    static let unlockButton = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.unlockButton")
    static let clearWaitList = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.clearWaitList")
    static let deleteQueueButtons = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.deleteQueueButtons")
    static let showDeleteQueuePopup = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.showDeleteQueuePopup")
}
