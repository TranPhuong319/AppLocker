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
        guard sysctl(&mib, 4, &proc, &size, nil, 0) == 0 else {
            return Date().addingTimeInterval(-5.0)
        }
        let sec = Double(proc.kp_proc.p_starttime.tv_sec)
        let usec = Double(proc.kp_proc.p_starttime.tv_usec) / 1_000_000.0
        return Date(timeIntervalSince1970: sec + usec).addingTimeInterval(-5.0)
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

enum LogLevelFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case info = "Info"
    case debug = "Debug"
    case notice = "Notice"
    case error = "Error"
    case fault = "Fault"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .all: return "All Levels"
        case .info: return "Info"
        case .debug: return "Debug"
        case .notice: return "Notice"
        case .error: return "Error"
        case .fault: return "Fault"
        }
    }

    var shortTag: String {
        switch self {
        case .all: return ""
        case .info: return "INFO"
        case .debug: return "DEBUG"
        case .notice: return "NOTICE"
        case .error: return "ERR"
        case .fault: return "FAULT"
        }
    }

    var osLogLevel: OSLogEntryLog.Level? {
        switch self {
        case .all: return nil
        case .info: return .info
        case .debug: return .debug
        case .notice: return .notice
        case .error: return .error
        case .fault: return .fault
        }
    }
}

// MARK: - App Log Entry

struct AppLogEntry: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let subsystem: String
    let category: String
    let level: OSLogEntryLog.Level
    let resolvedLevel: LogLevelFilter
    let message: String

    init(
        id: UUID = UUID(), date: Date, subsystem: String,
        category: String, level: OSLogEntryLog.Level, message: String
    ) {
        self.id = id; self.date = date; self.subsystem = subsystem
        self.category = category; self.level = level; self.message = message
        self.resolvedLevel = Self.resolveLevel(level: level)
    }

    var levelFilter: LogLevelFilter { resolvedLevel }

    var subsystemShort: String { subsystem.hasSuffix("ESExtension") ? "ESExt" : "App" }

    func formatted(dateFormatter: DateFormatter) -> String {
        let time = dateFormatter.string(from: date)
        let tag = "[\(subsystemShort)/\(category)] \(resolvedLevel.rawValue.uppercased())"
        return "\(time) \(tag): \(message)"
    }

    private static func resolveLevel(level: OSLogEntryLog.Level) -> LogLevelFilter {
        switch level {
        case .debug:
            return .debug
        case .info:
            return .info
        case .notice:
            return .notice
        case .fault:
            return .fault
        case .error:
            return .error
        default:
            return .info
        }
    }
}

// MARK: - Grouped Log Entry

struct GroupedLogEntry: Identifiable, Sendable {
    var id: UUID { entry.id }
    let entry: AppLogEntry
    let count: Int
}
