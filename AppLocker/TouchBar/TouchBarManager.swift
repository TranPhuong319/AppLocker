//
//  TouchBarManager.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//

import AppKit

class TouchBarManager: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarManager()

    // Lưu builder closure cho từng item
    private var items: [NSTouchBarItem.Identifier: () -> NSView] = [:]

    // Tạo TouchBar mới mỗi lần apply
    func makeTouchBar() -> NSTouchBar {
        let tb = NSTouchBar()
        tb.delegate = self
        tb.defaultItemIdentifiers = Array(items.keys)
        return tb
    }

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let viewBuilder = items[identifier] else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = viewBuilder()
        return item
    }

    /// Đăng ký mới hoặc ghi đè nếu đã có
    func registerOrUpdateItem(id: NSTouchBarItem.Identifier, builder: @escaping () -> NSView) {
        items[id] = builder
    }

    /// Bỏ item
    func unregisterItem(id: NSTouchBarItem.Identifier) {
        items.removeValue(forKey: id)
    }

    /// Apply touch bar cho 1 window
    func apply(to window: NSWindow?) {
        guard let window = window else { return }
        window.touchBar = makeTouchBar()
    }
}

// Định nghĩa identifier chung
extension NSTouchBarItem.Identifier {
    //MARK: Main Window
    static let addApp = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.addApp")
    //MARK: Popup Add Lock App
    static let lockButton = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.lockButton")
    static let closeAddPopupApp = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.closeAddPopupApp")
    static let addAppOther = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.addAppOther")
    //MARK: Popup Unlock App
    static let unlockButton = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.unlockButton")
    static let clearWaitList = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.clearWaitList")
}
    
