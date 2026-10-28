//
//  ActivitySettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 27/10/26.
//

import SwiftUI

// MARK: - Activity Settings Tab

struct ActivitySettingsTab: View {
    let isMock: Bool

    @AppStorage("activitySelectedTimeRange") private var storedTimeRange: LogTimeRange = .currentSession
    @State private var activityStore = ActivityStore()
    @State private var refreshTrigger: Int = 0

    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    init(isMock: Bool = false) {
        self.isMock = isMock
    }

    var body: some View {
        activityContent
            .searchable(text: $activityStore.searchText, prompt: "Search activity…")
            .toolbar {
                activityToolbarContent
            }
            .onAppear {
                guard !isMock else { return }
                activityStore.selectedTimeRange = storedTimeRange
                activityStore.startPolling()
            }
            .onChange(of: activityStore.selectedTimeRange) { _, newValue in
                storedTimeRange = newValue
            }
            .onDisappear {
                activityStore.stopPolling()
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsWindowWillClose)) { _ in
                activityStore.stopPolling()
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsWindowDidOpen)) { _ in
                guard !isMock else { return }
                activityStore.startPolling()
            }
    }

    // MARK: - Activity Content

    @ViewBuilder
    private var activityContent: some View {
        if activityStore.isLoading && activityStore.items.isEmpty {
            loadingPlaceholder
        } else if let error = activityStore.errorMessage, activityStore.items.isEmpty {
            errorPlaceholder(error)
        } else if activityStore.items.isEmpty {
            emptyPlaceholder
        } else {
            activityList
        }
    }

    private var activityList: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                LazyVStack(spacing: 8) {
                    ForEach(activityStore.items) { item in
                        ActivityRowView(
                            item: item,
                            currentDate: context.date,
                            dateFormatter: dateFormatter,
                            relativeFormatter: relativeFormatter
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Placeholders

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading activity…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorPlaceholder(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Could not load activity")
                .fontWeight(.medium)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "shield.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No Security Activity Found")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Security events like app locks, approvals, and tamper attempts will appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var activityToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Time Range", selection: $activityStore.selectedTimeRange) {
                ForEach(LogTimeRange.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)

            refreshButton

            Button(action: {
                activityStore.clearLogs()
            }, label: {
                Label("Clear Activity", systemImage: "trash")
            })
            .help("Clear current activity view")
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button(action: {
            refreshTrigger += 1
            guard !isMock else { return }
            activityStore.reload()
        }, label: {
            Label {
                Text("Refresh")
            } icon: {
                refreshIcon
            }
        })
        .help("Refresh activity")
    }

    @ViewBuilder
    private var refreshIcon: some View {
        if #available(macOS 15.0, *) {
            modernRefreshIcon
        } else {
            legacyRefreshIcon
        }
    }

    @available(macOS 15.0, *)
    @ViewBuilder
    private var modernRefreshIcon: some View {
        Image(systemName: "arrow.clockwise")
            .symbolEffect(.rotate.byLayer, value: refreshTrigger)
    }

    @ViewBuilder
    private var legacyRefreshIcon: some View {
        Image(systemName: "arrow.clockwise")
            .symbolEffect(.bounce.byLayer, value: refreshTrigger)
    }
}

#Preview {
    ActivitySettingsTab(isMock: true)
        .frame(width: 800, height: 500)
}
