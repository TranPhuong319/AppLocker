//
//  Log.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import OSLog

enum Logfile {
    static let core = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "AppLocker")
    static let launcher = Logger(subsystem: "com.TranPhuong319.Launcher", category: "Launcher")
}
