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

// MARK: - Log Selection Manager

@Observable
@MainActor
final class LogSelectionManager {
    var selectedIDs: Set<UUID> = []
    var lastSelectedIndex: Int?
    var isCopiedFeedback: Bool = false
    private var feedbackTask: Task<Void, Never>?

    var isDragging: Bool = false
    var dragSelectionRect: CGRect?
    private var initialSelectionBeforeDrag: Set<UUID> = []

    var hasSelection: Bool {
        !selectedIDs.isEmpty
    }

    var selectedCount: Int {
        selectedIDs.count
    }

    func isSelected(_ id: UUID) -> Bool {
        selectedIDs.contains(id)
    }

    func handleDragStart() {
        if !isDragging {
            isDragging = true
            initialSelectionBeforeDrag = selectedIDs
        }
    }

    func handleDragChanged(
        startLocation: CGPoint,
        currentLocation: CGPoint,
        entries: [GroupedLogEntry],
        rowFrames: [UUID: CGRect]
    ) {
        handleDragStart()

        let rect = CGRect(
            x: min(startLocation.x, currentLocation.x),
            y: min(startLocation.y, currentLocation.y),
            width: max(abs(currentLocation.x - startLocation.x), 1),
            height: max(abs(currentLocation.y - startLocation.y), 1)
        )
        dragSelectionRect = rect

        let isCommandHeld = NSEvent.modifierFlags.contains(.command)
        let isShiftHeld = NSEvent.modifierFlags.contains(.shift)

        let intersectingIndices = entries.enumerated().compactMap { index, item -> Int? in
            guard let frame = rowFrames[item.id] else { return nil }
            return (frame.minY <= rect.maxY && frame.maxY >= rect.minY) ? index : nil
        }

        guard let minIdx = intersectingIndices.min(), let maxIdx = intersectingIndices.max() else {
            if !isCommandHeld { selectedIDs.removeAll() }
            return
        }

        let draggedIDs = Set(entries[minIdx...maxIdx].map(\.id))

        if isCommandHeld {
            selectedIDs = initialSelectionBeforeDrag.union(draggedIDs)
        } else if isShiftHeld, let anchor = lastSelectedIndex, anchor < entries.count {
            let start = min(anchor, minIdx)
            let end = max(anchor, maxIdx)
            selectedIDs = Set(entries[start...end].map(\.id))
        } else {
            selectedIDs = draggedIDs
            lastSelectedIndex = minIdx
        }
    }

    func handleDragEnded() {
        isDragging = false
        dragSelectionRect = nil
        initialSelectionBeforeDrag.removeAll()
    }

    func handleRowClick(
        item: GroupedLogEntry,
        index: Int,
        entries: [GroupedLogEntry]
    ) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
                lastSelectedIndex = index
            }
        } else if modifiers.contains(.shift), let anchor = lastSelectedIndex, anchor < entries.count {
            let start = min(anchor, index)
            let end = max(anchor, index)
            let rangeIDs = entries[start...end].map(\.id)
            selectedIDs.formUnion(rangeIDs)
        } else {
            selectedIDs = [item.id]
            lastSelectedIndex = index
        }
    }

    func handleRowRightClick(item: GroupedLogEntry, index: Int) {
        if !selectedIDs.contains(item.id) {
            selectedIDs = [item.id]
            lastSelectedIndex = index
        }
    }

    func selectAll(entries: [GroupedLogEntry]) {
        selectedIDs = Set(entries.map(\.id))
    }

    func deselectAll() {
        selectedIDs.removeAll()
        lastSelectedIndex = nil
    }

    func copySelected(
        entries: [GroupedLogEntry],
        dateFormatter: DateFormatter
    ) {
        guard !selectedIDs.isEmpty else { return }
        let selected = entries.filter { selectedIDs.contains($0.id) }
        let text = selected
            .map { $0.entry.formatted(dateFormatter: dateFormatter) }
            .joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        triggerCopiedFeedback()
    }

    func copySingleEntry(
        _ entry: AppLogEntry,
        dateFormatter: DateFormatter
    ) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            entry.formatted(dateFormatter: dateFormatter),
            forType: .string
        )
    }

    func pruneInvalidSelection(validIDs: Set<UUID>) {
        if !selectedIDs.isSubset(of: validIDs) {
            selectedIDs.formIntersection(validIDs)
        }
    }

    private func triggerCopiedFeedback() {
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor in
            withAnimation(.snappy(duration: 0.25)) {
                self.isCopiedFeedback = true
            }
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.25)) {
                self.isCopiedFeedback = false
            }
        }
    }
}
