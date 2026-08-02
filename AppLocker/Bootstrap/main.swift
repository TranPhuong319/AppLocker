//
//  main.swift
//  AppLocker
//
//  Created by Doe Phương on 6/11/25.
//

import AppKit

// Tắt log rác hệ thống (AppIntents / OS Activity) và tự động đăng ký Shortcuts
setenv("OS_ACTIVITY_MODE", "disable", 1)
UserDefaults.standard.set(false, forKey: "NSAppIntentsEnabled")

// Tạo instance của app custom để chặn Cmd+Q
let app = CustomApplication.shared

// Gắn AppDelegate
let delegate = AppDelegate()
app.delegate = delegate

// Chạy vòng lặp chính
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
