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
    private static let maxItems = 2_000

    var rawItems: [SecurityActivityItem] = []
    var items: [SecurityActivityItem] = []
    var isLoading: Bool = true
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
    private let polling = LogPollingCoordinator(logTag: "ActivityStore")

    init(timeRange: LogTimeRange = .currentSession) {
        self.selectedTimeRange = timeRange
    }

    func startPolling() {
        clearedBeforeDate = nil
        polling.startPolling(
            onInitialLoad: { [weak self] in
                await self?.fetchActivities()
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
            await self?.fetchActivities()
        }
    }

    func clearLogs() {
        clearedBeforeDate = Date()
        rawItems.removeAll()
        items.removeAll()
    }

    func scheduleRefilter(debounceMs: UInt64 = 0) {
        polling.scheduleRefilter(debounceMs: debounceMs) { [weak self] in
            await self?.applyFilters()
        }
    }

    // MARK: - Private Fetching & Filtering

    private func queryActivities(since: Date, strictlyAfter: Bool) async throws -> [SecurityActivityItem] {
        let logEntries = try await LogReader.shared.query(since: since, strictlyAfter: strictlyAfter)
        return await Task.detached(priority: .userInitiated) {
            logEntries.compactMap { Self.parseSecurityEvent(from: $0) }
        }.value
    }

    private func fetchActivities() async {
        isLoading = true
        errorMessage = nil
        let since = selectedTimeRange.since

        do {
            let parsed = try await queryActivities(since: since, strictlyAfter: false)
            guard !Task.isCancelled else { return }

            let filtered = if let cleared = clearedBeforeDate {
                parsed.filter { $0.date > cleared }
            } else {
                parsed
            }

            self.rawItems = filtered
            await self.applyFilters()
            self.isLoading = false
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
            let newActivities = try await queryActivities(since: since, strictlyAfter: true)
            guard !Task.isCancelled, !newActivities.isEmpty else { return }

            self.rawItems.append(contentsOf: newActivities)
            if self.rawItems.count > Self.maxItems {
                self.rawItems.removeFirst(self.rawItems.count - Self.maxItems)
            }
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
            let sorted = filtered.sorted { $0.date > $1.date }
            return Self.groupActivities(sorted)
        }.value

        guard !Task.isCancelled else { return }
        self.items = results
    }
}
