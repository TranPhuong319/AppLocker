//
//  LogStore.swift
//  AppLocker
//
//  Created by Doe Phương on 30/9/25.
//

import Foundation
import OSLog
import Observation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared Log Polling & Debounce Coordinator

@MainActor
final class LogPollingCoordinator {
    private let logTag: String
    private var pollingTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?

    init(logTag: String) {
        self.logTag = logTag
    }

    func startPolling(
        onInitialLoad: @escaping @MainActor () async -> Void,
        onPollTick: @escaping @MainActor () async -> Void
    ) {
        pollingTask?.cancel()
        reload(operation: onInitialLoad)
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch is CancellationError {
                    break
                } catch {
                    let tag = self?.logTag ?? "Polling"
                    Logfile.app.warning(
                        """
                        [\(tag, privacy: .public)] Polling sleep interrupted: \
                        \(error.localizedDescription, privacy: .public)
                        """
                    )
                    break
                }
                guard !Task.isCancelled, self != nil else { break }
                await onPollTick()
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

    func reload(operation: @escaping @MainActor () async -> Void) {
        fetchTask?.cancel()
        fetchTask = Task {
            await operation()
        }
    }

    func scheduleRefilter(
        debounceMs: UInt64 = 0,
        operation: @escaping @MainActor () async -> Void
    ) {
        filterTask?.cancel()
        filterTask = Task { [weak self] in
            if debounceMs > 0 {
                do {
                    try await Task.sleep(for: .milliseconds(debounceMs))
                } catch is CancellationError {
                    return
                } catch {
                    let tag = self?.logTag ?? "Polling"
                    Logfile.app.warning(
                        """
                        [\(tag, privacy: .public)] Debounce sleep interrupted: \
                        \(error.localizedDescription, privacy: .public)
                        """
                    )
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await operation()
        }
    }
}

// MARK: - Log Store

@Observable
@MainActor
final class LogStore {
    private static let maxEntries = 2_000

    var entries: [AppLogEntry] = []
    var filteredEntries: [AppLogEntry] = []
    var groupedFilteredEntries: [GroupedLogEntry] = []
    var isLoading: Bool = true
    var errorMessage: String?

    var searchText: String = "" {
        didSet {
            guard oldValue != searchText else { return }
            scheduleRefilter(debounceMs: 150)
        }
    }

    var selectedTimeRange: LogTimeRange = .last24Hours {
        didSet {
            guard oldValue != selectedTimeRange else { return }
            reload()
        }
    }

    var selectedSubsystem: LogSubsystemFilter = .all {
        didSet { if oldValue != selectedSubsystem { scheduleRefilter() } }
    }

    var selectedLevel: LogLevelFilter = .all {
        didSet { if oldValue != selectedLevel { scheduleRefilter() } }
    }

    init(
        timeRange: LogTimeRange = .last24Hours,
        subsystem: LogSubsystemFilter = .all,
        level: LogLevelFilter = .all
    ) {
        self.selectedTimeRange = timeRange
        self.selectedSubsystem = subsystem
        self.selectedLevel = level
    }

    private var clearedBeforeDate: Date?
    private let polling = LogPollingCoordinator(logTag: "LogStore")

    func startPolling() {
        clearedBeforeDate = nil
        polling.startPolling(
            onInitialLoad: { [weak self] in
                await self?.fetchLogs()
            },
            onPollTick: { [weak self] in
                await self?.fetchLatest()
            }
        )
    }

    func stopPolling() {
        polling.stopPolling()
    }

    func reload() {
        clearedBeforeDate = nil
        polling.reload { [weak self] in
            await self?.fetchLogs()
        }
    }

    func clearLogs() {
        clearedBeforeDate = Date()
        entries.removeAll()
        filteredEntries.removeAll()
        groupedFilteredEntries.removeAll()
    }

    func scheduleRefilter(debounceMs: UInt64 = 0) {
        polling.scheduleRefilter(debounceMs: debounceMs) { [weak self] in
            await self?.applyFilters()
        }
    }

    func exportText(dateFormatter: DateFormatter) -> String {
        let header = """
            AppLocker Log Export
            Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))
            Range: \(selectedTimeRange.rawValue) | Process: \(selectedSubsystem.rawValue)
            Level: \(selectedLevel.rawValue)
            ───────────────────────────────────────────────────────────
            """
        let lines = filteredEntries.map { $0.formatted(dateFormatter: dateFormatter) }
        return ([header] + lines).joined(separator: "\n")
    }

    func groupedEntries(within windowSeconds: TimeInterval = 1.0) -> [GroupedLogEntry] {
        Self.groupEntries(filteredEntries, within: windowSeconds)
    }

    private struct LogGroupKey: Hashable {
        let subsystem: String
        let category: String
        let levelRawValue: Int
        let message: String
    }

    nonisolated static func groupEntries(
        _ source: [AppLogEntry],
        within windowSeconds: TimeInterval = 1.0
    ) -> [GroupedLogEntry] {
        guard !source.isEmpty else { return [] }
        var result: [GroupedLogEntry] = []
        result.reserveCapacity(source.count)
        var lastIndexByKey: [LogGroupKey: (index: Int, lastDate: Date)] = [:]

        for entry in source {
            let key = LogGroupKey(
                subsystem: entry.subsystem,
                category: entry.category,
                levelRawValue: entry.level.rawValue,
                message: entry.message
            )
            if let existing = lastIndexByKey[key],
               abs(entry.date.timeIntervalSince(existing.lastDate)) <= windowSeconds {
                let prev = result[existing.index]
                result[existing.index] = GroupedLogEntry(entry: prev.entry, count: prev.count + 1)
                lastIndexByKey[key] = (existing.index, entry.date)
            } else {
                lastIndexByKey[key] = (result.count, entry.date)
                result.append(GroupedLogEntry(entry: entry, count: 1))
            }
        }
        return result
    }

    private func performQuery(since: Date, strictlyAfter: Bool) async throws -> [AppLogEntry] {
        if let logQuery {
            return try await logQuery(since, strictlyAfter)
        }
        return try await LogReader.shared.query(since: since, strictlyAfter: strictlyAfter)
    }

    func fetchLatest() async {
        guard !isLoading else { return }
        let since = entries.last?.date ?? clearedBeforeDate ?? selectedTimeRange.since

        do {
            let newEntries = try await performQuery(since: since, strictlyAfter: true)
            guard !Task.isCancelled, !newEntries.isEmpty else { return }
            self.entries.append(contentsOf: newEntries)
            if self.entries.count > Self.maxEntries {
                self.entries.removeFirst(self.entries.count - Self.maxEntries)
            }
            await self.applyFilters()
        } catch {
            Logfile.app.error("[LogStore] Polling failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchLogs() async {
        isLoading = true
        errorMessage = nil
        let since = selectedTimeRange.since

        do {
            let parsed = try await LogReader.shared.query(since: since, strictlyAfter: false)
            guard !Task.isCancelled else { return }
            let filtered = if let cleared = clearedBeforeDate {
                parsed.filter { $0.date > cleared }
            } else {
                parsed
            }
            self.entries = filtered
            await self.applyFilters()
            self.isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            Logfile.app.error("[LogStore] Failed to fetch logs: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyFilters() async {
        guard !Task.isCancelled else { return }
        let snapshot = entries
        let search = searchText
        let subsystemFilter = selectedSubsystem
        let levelFilter = selectedLevel
        let timeCutoff = selectedTimeRange.since

        let (filtered, grouped) = await Task.detached(priority: .userInitiated) {
            let matches = snapshot.filter { entry in
                if Task.isCancelled { return false }

                let matchesTime = entry.date >= timeCutoff
                let matchesSearch = search.isEmpty
                    || entry.message.localizedCaseInsensitiveContains(search)
                    || entry.category.localizedCaseInsensitiveContains(search)

                let matchesSubsystem: Bool = {
                    guard let prefix = subsystemFilter.subsystemPrefix else { return true }
                    return subsystemFilter == .mainApp ? entry.subsystem == prefix : entry.subsystem.hasPrefix(prefix)
                }()

                let matchesLevel = levelFilter == .all || entry.resolvedLevel == levelFilter
                return matchesTime && matchesSearch && matchesSubsystem && matchesLevel
            }
            let grouped = Self.groupEntries(matches)
            return (matches, grouped)
        }.value

        guard !Task.isCancelled else { return }
        self.filteredEntries = filtered
        self.groupedFilteredEntries = grouped
    }
}

// MARK: - Log Reader Actor

actor LogReader {
    static let shared = LogReader()
    private static let maxReturnedEntries = 2_000

    func query(since: Date, strictlyAfter: Bool) throws -> [AppLogEntry] {
        let store = try OSLogStore(scope: .system)
        let position = store.position(date: since)
        let predicate = NSPredicate(format: "subsystem BEGINSWITH %@", "com.TranPhuong319.AppLocker")
        let rawEntries = try store.getEntries(at: position, matching: predicate)
        let items: [AppLogEntry] = rawEntries.compactMap { entry -> AppLogEntry? in
            guard let logEntry = entry as? OSLogEntryLog else { return nil }
            if strictlyAfter ? (logEntry.date <= since) : (logEntry.date < since) { return nil }
            // Break Obj-C __NSCFString bridging so Swift string comparisons stay native UTF-8
            var message = String(logEntry.composedMessage)
            message.makeContiguousUTF8()
            var subsystem = String(logEntry.subsystem)
            subsystem.makeContiguousUTF8()
            var category = String(logEntry.category)
            category.makeContiguousUTF8()
            return AppLogEntry(
                date: logEntry.date,
                subsystem: subsystem,
                category: category,
                level: logEntry.level,
                message: message
            )
        }
        let sorted = items.sorted { $0.date < $1.date }
        if sorted.count > Self.maxReturnedEntries {
            return Array(sorted.suffix(Self.maxReturnedEntries))
        }
        return sorted
    }
}

// MARK: - Export Document

struct LogTextDocument: FileDocument {
    static let logContentType = UTType(filenameExtension: "log", conformingTo: .plainText) ?? .plainText
    static let readableContentTypes: [UTType] = [logContentType, .plainText]
    let text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = "" }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
