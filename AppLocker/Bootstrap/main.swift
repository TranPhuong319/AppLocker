//
//  main.swift
//  AppLocker
//
//  Created by Doe Phương on 6/11/25.
//

import AppKit
import Darwin

#if !DEBUG
if getenv("DYLD_INSERT_LIBRARIES") != nil {
    fputs("[SECURITY] Malicious DYLD environment variables detected. Terminating process.\n", stderr)
    exit(127)
}
#endif

setenv("OS_ACTIVITY_MODE", "disable", 1)
UserDefaults.standard.set(false, forKey: "NSAppIntentsEnabled")

let app = CustomApplication.shared

let delegate = AppDelegate()
app.delegate = delegate

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
