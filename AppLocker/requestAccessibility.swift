//
//  requestAccessibility.swift
//  AppLocker
//
//  Created by Doe Phương on 26/07/2025.
//

import Cocoa
import ApplicationServices

func requestAccessibilityIfNeeded() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    let accessEnabled = AXIsProcessTrustedWithOptions(options)

    if !accessEnabled {
        print("⚠️ App chưa được cấp quyền Trợ năng. Đang yêu cầu người dùng cấp...")
    } else {
        print("✅ App đã có quyền Trợ năng.")
    }
}

