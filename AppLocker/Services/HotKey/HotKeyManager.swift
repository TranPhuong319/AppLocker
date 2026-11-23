//
//  HotKeyManager.swift
//  AppLocker
//
//  Created by Doe Phương on 7/12/25.
//

import AppKit
import Carbon

// MARK: - HotKey Shortcut Model
struct HotKeyShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var characters: String

    var keyEquivalent: String {
        characters.lowercased()
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += displayKeyName()
        return result
    }

    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Return): "⏎",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓"
    ]

    private func displayKeyName() -> String {
        Self.specialKeyNames[keyCode] ?? characters.uppercased()
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    static let defaultAppList = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_L),
        carbonModifiers: UInt32(cmdKey | shiftKey | controlKey),
        characters: "L"
    )

    static let defaultResumeProtection = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_L),
        carbonModifiers: UInt32(cmdKey | optionKey | controlKey),
        characters: "L"
    )
}

// MARK: - HotKey Persistence
extension HotKeyShortcut {
    private struct Storage: Codable {
        var shortcut: HotKeyShortcut?
    }

    private static let appListKey = "customHotkeyAppList"
    private static let resumeProtectionKey = "customHotkeyResumeProtection"

    static var currentAppList: HotKeyShortcut? {
        get { loadShortcut(forKey: appListKey, default: defaultAppList) }
        set { saveShortcut(newValue, forKey: appListKey) }
    }

    static var currentResumeProtection: HotKeyShortcut? {
        get { loadShortcut(forKey: resumeProtectionKey, default: defaultResumeProtection) }
        set { saveShortcut(newValue, forKey: resumeProtectionKey) }
    }

    private static func loadShortcut(forKey key: String, default fallback: HotKeyShortcut) -> HotKeyShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let storage = try? JSONDecoder().decode(Storage.self, from: data) else {
            return fallback
        }
        return storage.shortcut
    }

    private static func saveShortcut(_ shortcut: HotKeyShortcut?, forKey key: String) {
        if let data = try? JSONEncoder().encode(Storage(shortcut: shortcut)) {
            UserDefaults.standard.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: .hotKeySettingsDidChange, object: nil)
    }

    static var isCustomized: Bool {
        UserDefaults.standard.data(forKey: appListKey) != nil ||
        UserDefaults.standard.data(forKey: resumeProtectionKey) != nil
    }

    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: appListKey)
        UserDefaults.standard.removeObject(forKey: resumeProtectionKey)
        NotificationCenter.default.post(name: .hotKeySettingsDidChange, object: nil)
    }
}

// MARK: - HotKey Manager
/// Quản lý phím tắt toàn hệ thống (Global HotKey)
/// Dùng Carbon Event HotKey để chạy nền toàn hệ thống mà không cần xin quyền Accessibility.
@MainActor
final class HotKeyManager {
    private enum HotKeyAction: UInt32 {
        case appList = 1
        case resumeProtection = 2
    }

    private var appListHotKeyRef: EventHotKeyRef?
    private var resumeHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var protectionStatusObserver: (any NSObjectProtocol)?
    private var hotKeySettingsObserver: (any NSObjectProtocol)?

    init() {
        installEventHandler()
        reloadShortcuts()
        setupObservers()
    }

    isolated deinit {
        if let protectionStatusObserver {
            NotificationCenter.default.removeObserver(protectionStatusObserver)
        }
        if let hotKeySettingsObserver {
            NotificationCenter.default.removeObserver(hotKeySettingsObserver)
        }
        if let resumeHotKeyRef {
            UnregisterEventHotKey(resumeHotKeyRef)
        }
        if let appListHotKeyRef {
            UnregisterEventHotKey(appListHotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func setupObservers() {
        protectionStatusObserver = NotificationCenter.default.addObserver(
            forName: .protectionStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateResumeProtectionHotKey()
            }
        }

        hotKeySettingsObserver = NotificationCenter.default.addObserver(
            forName: .hotKeySettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadShortcuts()
            }
        }
    }

    func reloadShortcuts() {
        if let ref = appListHotKeyRef {
            UnregisterEventHotKey(ref)
            appListHotKeyRef = nil
        }
        if let shortcut = HotKeyShortcut.currentAppList {
            appListHotKeyRef = registerHotKey(
                id: .appList,
                keyCode: shortcut.keyCode,
                modifiers: shortcut.carbonModifiers
            )
        }
        updateResumeProtectionHotKey()
    }

    func updateResumeProtectionHotKey() {
        let isSuspended = LockES.shared.isProtectionDisabled
        if let ref = resumeHotKeyRef {
            UnregisterEventHotKey(ref)
            resumeHotKeyRef = nil
        }
        guard isSuspended, let shortcut = HotKeyShortcut.currentResumeProtection else {
            Logfile.app.info("[HotKey] Resume Protection hotkey inactive.")
            return
        }
        resumeHotKeyRef = registerHotKey(
            id: .resumeProtection,
            keyCode: shortcut.keyCode,
            modifiers: shortcut.carbonModifiers
        )
        Logfile.app.info("[HotKey] Registered Resume Protection (\(shortcut.displayString, privacy: .public)).")
    }

    private func installEventHandler() {
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

    @discardableResult
    private func registerHotKey(id: HotKeyAction, keyCode: UInt32, modifiers: UInt32) -> EventHotKeyRef? {
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
        guard registerStatus == noErr, let hotKeyRef else {
            Logfile.app.error(
                """
                [HotKey] Failed to register hotkey \(id.rawValue, privacy: .public): \
                \(registerStatus, privacy: .public)
                """
            )
            return nil
        }
        return hotKeyRef
    }
}

extension Notification.Name {
    static let hotKeySettingsDidChange = Notification.Name("hotKeySettingsDidChange")
}
