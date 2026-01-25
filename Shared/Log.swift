//
//  Log.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import OSLog
import Foundation

public extension Logger {
    /// Log dữ liệu nhạy cảm (SHA, Path, PID) với quyền riêng tư tự động:
    /// Public trong Debug và Private trong Release.
    func pLog(_ message: String) {
        #if DEBUG
        self.log(level: .default, "\(message, privacy: .public)")
        #else
        self.log(level: .default, "\(message, privacy: .private)")
        #endif
    }

    func pInfo(_ message: String) {
        #if DEBUG
        self.info("\(message, privacy: .public)")
        #else
        self.info("\(message, privacy: .private)")
        #endif
    }

    func pDebug(_ message: String) {
        #if DEBUG
        self.debug("\(message, privacy: .public)")
        #else
        self.debug("\(message, privacy: .private)")
        #endif
    }

    func pError(_ message: String) {
        #if DEBUG
        self.error("\(message, privacy: .public)")
        #else
        self.error("\(message, privacy: .private)")
        #endif
    }

    func pFault(_ message: String) {
        #if DEBUG
        self.fault("\(message, privacy: .public)")
        #else
        self.fault("\(message, privacy: .private)")
        #endif
    }
}

public enum Logfile {
    public static let core = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "AppLocker")
    public static let launcher = Logger(subsystem: "com.TranPhuong319.AppLocker.Launcher", category: "AppLocker.Launcher")
    public static let es = Logger(subsystem: "com.TranPhuong319.AppLocker.ESExtension", category: "AppLocker.ESExtension")
    public static let keychain = Logger(subsystem: "com.TranPhuong319.AppLocker.ESExtension", category: "AppLocker.KeychainAccess")
}
