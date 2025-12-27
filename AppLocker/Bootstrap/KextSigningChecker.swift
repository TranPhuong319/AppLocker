//
//  KextSigningChecker.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation
import IOKit

func isKextSigningDisabled() -> Bool {
    // 1. Lấy tham chiếu đến registry entry của NVRAM (nằm trong "options")
    let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/options")
    if entry == 0 { return false }
    // Đảm bảo giải phóng object sau khi dùng xong để tránh leak bộ nhớ
    defer { IOObjectRelease(entry) }

    // 2. Truy vấn thuộc tính "csr-active-config"
    guard let property = IORegistryEntryCreateCFProperty(
        entry, "csr-active-config" as CFString, kCFAllocatorDefault, 0) else {
        return false
    }
    let data = property.takeRetainedValue() as? Data

    // 3. Kiểm tra byte đầu tiên (Bit 0 là ALLOW_UNTRUSTED_KEXTS)
    if let bytes = data, !bytes.isEmpty {
        // CSR_ALLOW_UNTRUSTED_KEXTS = 0x01
        return (bytes[0] & 0x01) != 0
    }

    return false
}
