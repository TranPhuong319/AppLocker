//
//  Log.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import OSLog

enum Logfile {
    static let core = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "AppLocker")
    static let launcher = Logger(subsystem: "com.TranPhuong319.AppLocker.Launcher", category: "AppLocker.Launcher")
    static let es = Logger(subsystem: "com.TranPhuong319.AppLocker.ESExtension", category: "AppLocker.ESExtension")
}
