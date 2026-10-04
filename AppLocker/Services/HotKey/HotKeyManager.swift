//
//  HotKeyManager.swift
//  AppLocker
//
//  Created by Doe Phương on 7/12/25.
//

import AppKit
import Carbon

/// Quản lý phím tắt toàn hệ thống (Global HotKey)
/// Dùng Carbon Event HotKey để chạy nền toàn hệ thống mà không cần xin quyền Accessibility.
final class HotKeyManager {
    private enum HotKeyAction: UInt32 {
        case appList = 1
        case resumeProtection = 2
    }

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?

    init() {
        registerShortcuts()
    }

    deinit {
        unregisterShortcuts()
    }

    private func registerShortcuts() {
        registerHotKey(id: .appList, keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | shiftKey))
        registerHotKey(id: .resumeProtection, keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | optionKey))

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, let action = HotKeyAction(rawValue: hotKeyID.id) else {
                return noErr
            }

            Task { @MainActor in
                switch action {
                case .appList:
                    NSApp.appDelegate?.openAppList()
                case .resumeProtection:
                    NSApp.appDelegate?.resumeProtection()
                }
            }
            return noErr
        }, 1, &eventType, nil, &eventHandlerRef)
    }

    private func registerHotKey(id: HotKeyAction, keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(1), id: id.rawValue)
        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus == noErr, let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
        }
    }

    private func unregisterShortcuts() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
