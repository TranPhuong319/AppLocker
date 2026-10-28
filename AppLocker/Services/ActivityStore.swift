//
//  ActivityStore.swift
//  AppLocker
//
//  Created by Doe Phương on 27/10/26.
//

import Foundation
import Observation
import OSLog
import SwiftUI

// MARK: - Activity Store

@Observable
@MainActor
final class ActivityStore {
    var rawItems: [SecurityActivityItem] = []
    var items: [SecurityActivityItem] = []
    var isLoading: Bool = false
    var errorMessage: String?

    var searchText: String = "" {
        didSet {
            guard oldValue != searchText else { return }
            scheduleRefilter(debounceMs: 150)
        }
    }

    var selectedTimeRange: LogTimeRange = .currentSession {
        didSet {
            guard oldValue != selectedTimeRange else { return }
            reload()
        }
    }

    private var clearedBeforeDate: Date?
    private var fetchTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    init(timeRange: LogTimeRange = .currentSession) {
        self.selectedTimeRange = timeRange
    }

    func startPolling() {
        pollingTask?.cancel()
        reload()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { break }
                await self.fetchLatest()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        fetchTask?.cancel()
        fetchTask = nil
        filterTask?.cancel()
        filterTask = nil
    }

    func reload() {
        clearedBeforeDate = nil
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            await self?.fetchActivities()
        }
    }

    func clearLogs() {
        clearedBeforeDate = Date()
        rawItems.removeAll()
        items.removeAll()
    }

    func scheduleRefilter(debounceMs: UInt64 = 0) {
        filterTask?.cancel()
        filterTask = Task { [weak self] in
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
            }
            guard !Task.isCancelled, let self else { return }
            await self.applyFilters()
        }
    }

    // MARK: - Private Fetching & Parsing

    private func fetchActivities() async {
        isLoading = true
        errorMessage = nil
        let since = selectedTimeRange.since

        do {
            let logEntries = try await LogReader.shared.query(since: since, strictlyAfter: false)
            guard !Task.isCancelled else { return }

            let parsed = logEntries.compactMap { Self.parseSecurityEvent(from: $0) }
            let filtered = if let cleared = clearedBeforeDate {
                parsed.filter { $0.date > cleared }
            } else {
                parsed
            }

            self.rawItems = filtered
            self.isLoading = false
            await self.applyFilters()
        } catch {
            guard !Task.isCancelled else { return }
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            Logfile.app.error(
                "[ActivityStore] Failed to fetch activities: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func fetchLatest() async {
        guard !isLoading else { return }
        let since = rawItems.last?.date ?? clearedBeforeDate ?? selectedTimeRange.since

        do {
            let newLogEntries = try await LogReader.shared.query(since: since, strictlyAfter: true)
            guard !Task.isCancelled, !newLogEntries.isEmpty else { return }

            let newActivities = newLogEntries.compactMap { Self.parseSecurityEvent(from: $0) }
            guard !newActivities.isEmpty else { return }

            self.rawItems.append(contentsOf: newActivities)
            await self.applyFilters()
        } catch {
            Logfile.app.error("[ActivityStore] Polling failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyFilters() async {
        guard !Task.isCancelled else { return }
        let snapshot = rawItems
        let search = searchText
        let timeCutoff = selectedTimeRange.since

        let results = await Task.detached(priority: .userInitiated) { () -> [SecurityActivityItem] in
            let filtered = snapshot.filter { item in
                if Task.isCancelled { return false }
                guard item.date >= timeCutoff else { return false }
                if search.isEmpty { return true }
                return item.targetAppName.localizedCaseInsensitiveContains(search)
                    || (item.senderName?.localizedCaseInsensitiveContains(search) ?? false)
                    || (item.targetAppPath?.localizedCaseInsensitiveContains(search) ?? false)
            }
            // Sort newest first
            let sorted = filtered.sorted { $0.date > $1.date }
            return Self.groupActivities(sorted)
        }.value

        guard !Task.isCancelled else { return }
        self.items = results
    }

    // MARK: - 30s Grouping & Parsing Heuristics

    nonisolated static func groupActivities(
        _ items: [SecurityActivityItem],
        windowSeconds: TimeInterval = 30.0
    ) -> [SecurityActivityItem] {
        guard !items.isEmpty else { return [] }
        var result: [SecurityActivityItem] = []
        var current = items[0]

        for item in items.dropFirst() {
            let isSameTarget = item.targetAppName == current.targetAppName
            let isSameType = item.type == current.type
            let isSameReason = item.denialReason == current.denialReason
            let isWithinWindow = abs(item.date.timeIntervalSince(current.date)) <= windowSeconds

            if isSameTarget && isSameType && isSameReason && isWithinWindow {
                current.repeatCount += item.repeatCount
            } else {
                result.append(current)
                current = item
            }
        }
        result.append(current)
        return result
    }

    nonisolated static func parseSecurityEvent(from entry: AppLogEntry) -> SecurityActivityItem? {
        let msg = entry.message
        if msg.contains("[SecurityEvent:Approved]") {
            return parseSimpleSecurityEvent(type: .approved, message: msg, date: entry.date)
        } else if msg.contains("[SecurityEvent:Rejected]") {
            return parseSimpleSecurityEvent(type: .rejected, message: msg, date: entry.date)
        } else if msg.contains("[SecurityEvent:TamperBlocked]") {
            return parseTamperSecurityEvent(message: msg, date: entry.date)
        }
        return nil
    }

    nonisolated private static func parseSimpleSecurityEvent(
        type: SecurityEventType,
        message: String,
        date: Date
    ) -> SecurityActivityItem? {
        guard let appRange = message.range(of: "App: ") else { return nil }
        let afterApp = message[appRange.upperBound...]
        guard let pidRange = afterApp.range(of: " (PID ") else { return nil }
        let appName = String(afterApp[..<pidRange.lowerBound]).trimmingCharacters(in: .whitespaces)

        let afterPid = afterApp[pidRange.upperBound...]
        guard let closeParenRange = afterPid.range(of: ")") else { return nil }
        let pidStr = String(afterPid[..<closeParenRange.lowerBound])
        guard let pid = Int32(pidStr) else { return nil }

        var path: String?
        if let pathRange = message.range(of: " | Path: ") {
            let afterStart = message[pathRange.upperBound...]
            if let reasonRange = afterStart.range(of: " | Reason: ") {
                path = String(afterStart[..<reasonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            } else {
                path = String(afterStart).trimmingCharacters(in: .whitespaces)
            }
        }

        var denialReason: DenialReason?
        if type == .rejected {
            if message.contains("Reason: Timeout") {
                denialReason = .timedOut
            } else if message.contains("Reason: UserCancel") {
                denialReason = .userCancelled
            }
        }

        return SecurityActivityItem(
            date: date,
            type: type,
            targetAppName: appName,
            targetAppPath: path,
            targetPid: pid,
            denialReason: denialReason
        )
    }

    nonisolated private static func parseTamperSecurityEvent(message: String, date: Date) -> SecurityActivityItem? {
        guard let targetRange = message.range(of: "Target: ") else { return nil }
        let afterTarget = message[targetRange.upperBound...]
        guard let targetPidRange = afterTarget.range(of: " (PID ") else { return nil }
        let targetName = String(afterTarget[..<targetPidRange.lowerBound]).trimmingCharacters(in: .whitespaces)

        let afterTargetPid = afterTarget[targetPidRange.upperBound...]
        guard let targetCloseParen = afterTargetPid.range(of: ")") else { return nil }
        guard let targetPid = Int32(afterTargetPid[..<targetCloseParen.lowerBound]) else { return nil }

        var senderName: String?
        var senderPid: Int32?
        if let senderRange = message.range(of: " | Sender: ") {
            let afterSender = message[senderRange.upperBound...]
            if let sPidRange = afterSender.range(of: " (PID ") {
                senderName = String(afterSender[..<sPidRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let afterSPid = afterSender[sPidRange.upperBound...]
                if let sClose = afterSPid.range(of: ")") {
                    senderPid = Int32(afterSPid[..<sClose.lowerBound])
                }
            } else if let endRange = afterSender.range(of: " | ") {
                senderName = String(afterSender[..<endRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }

        var senderPath: String?
        if let pathRange = message.range(of: " | SenderPath: ") {
            senderPath = String(message[pathRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        return SecurityActivityItem(
            date: date,
            type: .tamperBlocked,
            targetAppName: targetName,
            targetPid: targetPid,
            senderName: senderName,
            senderPid: senderPid,
            senderPath: senderPath
        )
    }
}
