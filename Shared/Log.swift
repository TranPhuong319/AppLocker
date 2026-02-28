//
//  Log.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import OSLog
import Foundation

public enum Logfile {
    public static let core = Logger(
        subsystem: "com.TranPhuong319.AppLocker",
        category: "AppLocker"
    )
    public static let launcher = Logger(
        subsystem: "com.TranPhuong319.AppLocker.Launcher",
        category: "AppLocker.Launcher"
    )
    public static let endpointSecurity = Logger(
        subsystem: "com.TranPhuong319.AppLocker.ESExtension",
        category: "AppLocker.ESExtension"
    )
    public static let keychain = Logger(
        subsystem: "com.TranPhuong319.AppLocker.ESExtension",
        category: "AppLocker.KeychainAccess"
    )
}
