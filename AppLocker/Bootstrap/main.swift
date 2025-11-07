//
//  main.swift
//  AppLocker
//
//  Created by Doe Phương on 6/11/25.
//

import AppKit

// Tạo instance của app custom để chặn Cmd+Q
_ = CustomApplication.shared
let app = CustomApplication.shared

// Gắn AppDelegate
let delegate = AppDelegate()
app.delegate = delegate

// Chạy vòng lặp chính
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
