//
//  HotKeyManager.swift
//  AppLocker
//
//  Created by Doe Phương on 7/12/25.
//

import Cocoa
import Carbon

class HotKeyManager {
    var hotKeyRef: EventHotKeyRef?
    var hotKeyID = EventHotKeyID()

    init() {
        hotKeyID.signature = OSType("HTK1".utf8.reduce(0) { $0 << 8 | OSType($1) })
        hotKeyID.id = 1

        let modifierKeys: UInt32 = UInt32(cmdKey | shiftKey)   // Cmd + Shift
        let keyCode: UInt32 = UInt32(kVK_ANSI_L)               // phím L

        RegisterEventHotKey(keyCode,
                            modifierKeys,
                            hotKeyID,
                            GetEventDispatcherTarget(),
                            0,
                            &hotKeyRef)

        installHandler()
    }

    func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetEventDispatcherTarget(), { (_, event, _) -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event,
                              UInt32(kEventParamDirectObject),
                              UInt32(typeEventHotKeyID),
                              nil,
                              MemoryLayout.size(ofValue: id),
                              nil,
                              &id)

            if id.id == 1 {
                NSApp.appDelegate?.openListApp()
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
