//
//  KextSigningChecker.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation

func isKextSigningDisabled() -> Bool {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/nvram")
    proc.arguments = ["csr-active-config"]

    let outPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = Pipe()

    do {
        try proc.run()
    } catch {
        return false
    }
    proc.waitUntilExit()

    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    guard let raw = String(data: data, encoding: .utf8) else { return false }

    // Tìm mọi cặp hex theo mẫu %xx
    let pattern = "%([0-9A-Fa-f]{2})"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
    let ns = raw as NSString
    let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))

    var bytes = [UInt8]()
    for m in matches {
        let hex = ns.substring(with: m.range(at: 1))
        if let b = UInt8(hex, radix: 16) {
            bytes.append(b)
        }
    }

    if bytes.isEmpty { return false }

    // Ghép tối đa 4 byte theo little-endian vào UInt32
    var mask: UInt32 = 0
    for (i, b) in bytes.enumerated() {
        if i >= 4 { break }
        mask |= UInt32(b) << (8 * i)
    }

    // ALLOW_UNTRUSTED_KEXTS = 0x1 -> kiểm tra bit 0
    return (mask & 0x1) != 0
}
