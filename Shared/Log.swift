//
//  Log.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import OSLog
import Foundation

public enum Logfile {
    // MARK: - Main App Subsystem (com.TranPhuong319.AppLocker)
    public static let app = Logger(
        subsystem: "com.TranPhuong319.AppLocker",
        category: "App"
    )
    public static let policy = Logger(
        subsystem: "com.TranPhuong319.AppLocker",
        category: "Policy"
    )
    public static let appXPC = Logger(
        subsystem: "com.TranPhuong319.AppLocker",
        category: "XPC"
    )
    public static let security = Logger(
        subsystem: "com.TranPhuong319.AppLocker",
        category: "Security"
    )

    // MARK: - ESExtension Subsystem (com.TranPhuong319.AppLocker.ESExtension)
    public static let endpointSecurity = Logger(
        subsystem: "com.TranPhuong319.AppLocker.ESExtension",
        category: "EndpointSecurity"
    )
    public static let esXPC = Logger(
        subsystem: "com.TranPhuong319.AppLocker.ESExtension",
        category: "XPC"
    )
    public static let esSecurity = Logger(
        subsystem: "com.TranPhuong319.AppLocker.ESExtension",
        category: "Security"
    )
}
