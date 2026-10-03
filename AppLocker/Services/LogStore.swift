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

// MARK: - Log Entry

struct AppLogEntry: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let subsystem: String
    let category: String
    let level: OSLogEntryLog.Level
    let message: String

    init(
        id: UUID = UUID(), date: Date, subsystem: String,
        category: String, level: OSLogEntryLog.Level, message: String
    ) {
        self.id = id; self.date = date; self.subsystem = subsystem
        self.category = category; self.level = level; self.message = message
    }

    var levelFilter: LogLevelFilter {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .error: return .error
        case .fault: return .fault
        default: return .info
        }
    }

    var subsystemShort: String { subsystem.hasSuffix("ESExtension") ? "ESExt" : "App" }

    func formatted(dateFormatter: DateFormatter) -> String {
        let time = dateFormatter.string(from: date)
        let tag = "[\(subsystemShort)/\(category)] \(levelFilter.rawValue.uppercased())"
        return "\(time) \(tag): \(message)"
    }
}

// MARK: - Grouped Log Entry

struct GroupedLogEntry: Identifiable, Sendable {
    var id: UUID { entry.id }
    let entry: AppLogEntry
    let count: Int
}

// MARK: - Log Store

@Observable
@MainActor
final class LogStore {
    var entries: [AppLogEntry] = []
    var filteredEntries: [AppLogEntry] = []
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

    var selectedSubsystem: LogSubsystemFilter = .all {
        didSet { if oldValue != selectedSubsystem { scheduleRefilter() } }
    }

    var selectedLevel: LogLevelFilter = .all {
        didSet { if oldValue != selectedLevel { scheduleRefilter() } }
    }

    private var clearedBeforeDate: Date?
    private var fetchTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    func startPolling() {
        pollingTask?.cancel()
        reload()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
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
            await self?.fetchLogs()
        }
    }

    func clearLogs() {
        clearedBeforeDate = Date()
        entries.removeAll()
        filteredEntries.removeAll()
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
        guard !filteredEntries.isEmpty else { return [] }
        var result: [GroupedLogEntry] = []
        var current = filteredEntries[0]
        var count = 1
        var lastDate = current.date

        for entry in filteredEntries.dropFirst() {
            let isSame = entry.subsystem == current.subsystem
                && entry.category == current.category
                && entry.level == current.level
                && entry.message == current.message
            let isWithinWindow = abs(entry.date.timeIntervalSince(lastDate)) <= windowSeconds

            if isSame && isWithinWindow {
                count += 1
                lastDate = entry.date
            } else {
                result.append(GroupedLogEntry(entry: current, count: count))
                current = entry
                count = 1
                lastDate = entry.date
            }
        }
        result.append(GroupedLogEntry(entry: current, count: count))
        return result
    }

    func fetchLatest() async {
        guard !isLoading else { return }
        let since = entries.last?.date ?? clearedBeforeDate ?? selectedTimeRange.since

        do {
            let newEntries = try await LogReader.shared.query(since: since, strictlyAfter: true)
            guard !Task.isCancelled, !newEntries.isEmpty else { return }
            self.entries.append(contentsOf: newEntries)
            await self.applyFilters()
        } catch {}
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
            self.isLoading = false
            await self.applyFilters()
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

        let results = await Task.detached(priority: .userInitiated) { () -> [AppLogEntry] in
            snapshot.filter { entry in
                if Task.isCancelled { return false }

                let matchesSearch = search.isEmpty
                    || entry.message.localizedCaseInsensitiveContains(search)
                    || entry.category.localizedCaseInsensitiveContains(search)

                let matchesSubsystem: Bool = {
                    guard let prefix = subsystemFilter.subsystemPrefix else { return true }
                    return subsystemFilter == .mainApp ? entry.subsystem == prefix : entry.subsystem.hasPrefix(prefix)
                }()

                let matchesLevel = levelFilter.osLogLevel == nil || entry.level == levelFilter.osLogLevel
                return matchesSearch && matchesSubsystem && matchesLevel
            }
        }.value

        guard !Task.isCancelled else { return }
        self.filteredEntries = results
    }
}

// MARK: - Log Reader Actor

private actor LogReader {
    static let shared = LogReader()

    func query(since: Date, strictlyAfter: Bool) throws -> [AppLogEntry] {
        let store = try OSLogStore(scope: .system)
        let position = store.position(date: since)
        let predicate = NSPredicate(format: "subsystem BEGINSWITH %@", "com.TranPhuong319.AppLocker")
        let rawEntries = try store.getEntries(at: position, matching: predicate)
        let items: [AppLogEntry] = rawEntries.compactMap { entry -> AppLogEntry? in
            guard let logEntry = entry as? OSLogEntryLog else { return nil }
            if strictlyAfter, logEntry.date <= since { return nil }
            return AppLogEntry(
                date: logEntry.date,
                subsystem: logEntry.subsystem,
                category: logEntry.category,
                level: logEntry.level,
                message: logEntry.composedMessage
            )
        }
        return items.sorted { $0.date < $1.date }
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
