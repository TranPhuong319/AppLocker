//
//  Log.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//


import OSLog

enum Log {
    static let core = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "Core")
    static let helper = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "Helper")
    static let launcher = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "Launcher")
}
