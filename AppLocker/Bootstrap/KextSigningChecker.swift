//
//  KextSigningChecker.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation

func isKextSigningDisabled() -> Bool {
    let process = Process()
    process.launchPath = "/usr/bin/env"
    process.arguments = ["csrutil", "status"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    process.launch()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
        return false
    }

    // Kiểm tra chuỗi trong output
    if output.contains("Kext Signing: disabled") {
        return true
    }
    return false
}
