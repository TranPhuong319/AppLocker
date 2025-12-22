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

        // EN: Listen for selection or locking state to update lock button.
        // VI: Lắng nghe thay đổi chọn/đang khóa để cập nhật nút Lock.
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
                // EN: Full-width container for a prominent red button.
                // VI: Container toàn chiều rộng cho nút đỏ nổi bật.
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
                    button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
                    button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 0),
                    button.topAnchor.constraint(equalTo: container.topAnchor),
                    button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    button.heightAnchor.constraint(equalToConstant: 30)
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

    // EN: Remove all cached items.
    // VI: Xóa tất cả item đã lưu.
    func clear() {
        items.removeAll()
    }

    // EN: Register or update a custom item builder.
    // VI: Đăng ký hoặc cập nhật builder cho item tùy chỉnh.
    func registerOrUpdateItem(id: NSTouchBarItem.Identifier, builder: @escaping () -> NSView) {
        items[id] = builder
    }

    // EN: Apply a touch bar layout to a window for a given type.
    // VI: Áp dụng bố cục touch bar cho một cửa sổ theo loại.
    func apply(to window: NSWindow?, type: AppState.TouchBarType) {
        guard let window else { return }
        window.touchBar = makeTouchBar(for: type)
    }
}

// EN: Common item identifiers.
// VI: Định danh item dùng chung.
extension NSTouchBarItem.Identifier {
    // EN: Main Window
    // VI: Cửa sổ chính
    static let addApp = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.addApp")
    // EN: Popup Add Lock App
    // VI: Popup thêm ứng dụng khóa
    static let lockButton = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.lockButton")
    static let closeAddPopupApp = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.closeAddPopupApp")
    static let addAppOther = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.addAppOther")
    static let centerButtonsLock = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.centerButtonsLock")
    // EN: Popup Unlock App
    // VI: Popup mở khóa ứng dụng
    static let unlockButton = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.unlockButton")
    static let clearWaitList = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.clearWaitList")
    static let deleteQueueButtons = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.deleteQueueButtons")
    static let showDeleteQueuePopup = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.showDeleteQueuePopup")
}
