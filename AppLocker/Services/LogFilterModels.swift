//
//  LogFilterModels.swift
//  AppLocker
//
//  Created by Doe Phương on 30/9/25.
//

import Darwin
import Foundation
import OSLog
import SwiftUI
import AppKit

// MARK: - Log Time Range

enum LogTimeRange: String, CaseIterable, Identifiable {
    case currentSession = "Current Session"
    case lastHour = "Last Hour"
    case last6Hours = "Last 6 Hours"
    case last24Hours = "Last 24 Hours"
    case last7Days = "Last 7 Days"
    case all = "All Time"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .currentSession: return "Current Session"
        case .lastHour: return "Last Hour"
        case .last6Hours: return "Last 6 Hours"
        case .last24Hours: return "Last 24 Hours"
        case .last7Days: return "Last 7 Days"
        case .all: return "All Time"
        }
    }

    private static let sessionStartTime: Date = {
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &proc, &size, nil, 0) == 0 else { return Date() }
        let sec = Double(proc.kp_proc.p_starttime.tv_sec)
        let usec = Double(proc.kp_proc.p_starttime.tv_usec) / 1_000_000.0
        return Date(timeIntervalSince1970: sec + usec)
    }()

    var since: Date {
        let now = Date()
        switch self {
        case .currentSession: return Self.sessionStartTime
        case .lastHour: return now.addingTimeInterval(-3600)
        case .last6Hours: return now.addingTimeInterval(-6 * 3600)
        case .last24Hours: return now.addingTimeInterval(-86400)
        case .last7Days: return now.addingTimeInterval(-7 * 86400)
        case .all: return .distantPast
        }
    }
}

// MARK: - Log Subsystem Filter

enum LogSubsystemFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case mainApp = "Main App"
    case esExtension = "ES Extension"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .all: return "All Processes"
        case .mainApp: return "Main App"
        case .esExtension: return "ES Extension"
        }
    }

    var subsystemPrefix: String? {
        switch self {
        case .all: return nil
        case .mainApp: return "com.TranPhuong319.AppLocker"
        case .esExtension: return "com.TranPhuong319.AppLocker.ESExtension"
        }
    }
}

// MARK: - Log Level Filter

enum LogLevelFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case debug = "Debug"
    case info = "Info"
    case notice = "Notice"
    case error = "Error"
    case fault = "Fault"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .all: return "All Levels"
        case .debug: return "Debug"
        case .info: return "Info"
        case .notice: return "Notice"
        case .error: return "Error"
        case .fault: return "Fault"
        }
    }

    var osLogLevel: OSLogEntryLog.Level? {
        switch self {
        case .all: return nil
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .error: return .error
        case .fault: return .fault
        }
    }
}
