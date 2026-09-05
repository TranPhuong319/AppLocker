//
//  HotKeyManager.swift
//  AppLocker
//
//  Created by Doe Phương on 7/12/25.
//

import Cocoa
import Carbon

/// Quản lý phím tắt toàn hệ thống (Global HotKey: ⌘ + ⇧ + L)
/// Dùng Carbon Event HotKey để chạy nền toàn hệ thống mà không cần xin quyền Accessibility.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init() {
        registerShortcut()
    }

    deinit {
        unregisterShortcut()
    }

    private func registerShortcut() {
        // 1. Đăng ký phím tắt ⌘ + ⇧ + L với hệ thống
        let hotKeyID = EventHotKeyID(signature: OSType(1), id: 1)
        let modifierKeys = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(kVK_ANSI_L)

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifierKeys,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else { return }

        // 2. Lắng nghe sự kiện khi phím tắt được nhấn
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            Task { @MainActor in
                NSApp.appDelegate?.openAppList()
            }
            return noErr
        }, 1, &eventType, nil, &eventHandlerRef)
    }

    private func unregisterShortcut() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}
