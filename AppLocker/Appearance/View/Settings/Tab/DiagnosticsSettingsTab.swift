//
//  DiagnosticsSettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 30/9/25.
//

import SwiftUI
import OSLog
import UniformTypeIdentifiers

// MARK: - Diagnostics Settings Tab

struct DiagnosticsSettingsTab: View {
    let isMock: Bool

    @AppStorage("collapseRepeatingLogs") var collapseRepeatingLogs: Bool = true
    @AppStorage("logsSelectedTimeRange") var storedTimeRange: LogTimeRange = .currentSession
    @AppStorage("logsSelectedSubsystem") var storedSubsystem: LogSubsystemFilter = .all
    @AppStorage("logsSelectedLevel") var storedLevel: LogLevelFilter = .all
    @State var logStore = LogStore()
    @State var selectionManager = LogSelectionManager()
    @State var isExporting: Bool = false
    @State var isExportSuccess: Bool = false
    @State var resetExportTask: Task<Void, Never>?
    @State var refreshTrigger: Int = 0
    @State var isAtBottom: Bool = true
    @State var scrollToBottomTrigger: Int = 0
    @FocusState var isSearchFocused: Bool
    @Environment(\.controlActiveState) var controlActiveState

    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var displayEntries: [GroupedLogEntry] {
        collapseRepeatingLogs
            ? logStore.groupedEntries()
            : logStore.filteredEntries.map { GroupedLogEntry(entry: $0, count: 1) }
    }

    init(isMock: Bool = false) {
        self.isMock = isMock
    }

    var body: some View {
        diagnosticsListContent
            .searchable(text: $logStore.searchText, prompt: "Search logs…")
            .modifier(LogSearchFocusModifier(isFocused: $isSearchFocused))
            .toolbar {
                diagnosticsToolbarContent
            }
            .task {
                guard !isMock else { return }
                logStore.selectedTimeRange = storedTimeRange
                logStore.selectedSubsystem = storedSubsystem
                logStore.selectedLevel = storedLevel
                logStore.startPolling()
            }
            .onChange(of: logStore.selectedTimeRange) { _, newValue in
                storedTimeRange = newValue
            }
            .onChange(of: logStore.selectedSubsystem) { _, newValue in
                storedSubsystem = newValue
            }
            .onChange(of: logStore.selectedLevel) { _, newValue in
                storedLevel = newValue
            }
            .onDisappear { logStore.stopPolling() }
            .onReceive(NotificationCenter.default.publisher(for: .settingsWindowWillClose)) { _ in
                logStore.stopPolling()
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsWindowDidOpen)) { _ in
                guard !isMock else { return }
                logStore.startPolling()
            }
            .fileExporter(
                isPresented: $isExporting,
                document: LogTextDocument(text: logStore.exportText(dateFormatter: dateFormatter)),
                contentType: LogTextDocument.logContentType,
                defaultFilename: exportFilename
            ) { result in
                if case .success = result {
                    handleExportSuccess()
                }
            }
    }

    // MARK: - Diagnostics Content

    @ViewBuilder
    private var diagnosticsListContent: some View {
        if logStore.isLoading && logStore.filteredEntries.isEmpty {
            loadingPlaceholder
        } else if let error = logStore.errorMessage, logStore.filteredEntries.isEmpty {
            errorPlaceholder(error)
        } else if logStore.filteredEntries.isEmpty {
            emptyPlaceholder
        } else {
            diagnosticsTableView
        }
    }
}

// MARK: - Row Copy Button

struct LogRowCopyButton: View {
    let entry: AppLogEntry
    let dateFormatter: DateFormatter
    @State private var isCopied: Bool = false

    var body: some View {
        Button(action: copyEntry) {
            copyIcon
        }
        .buttonStyle(.plain)
        .help("Copy entry")
        .accessibilityLabel("Copy log entry")
    }

    @ViewBuilder
    private var copyIcon: some View {
        let iconColor = isCopied ? Color.green : Color.secondary

        if #available(macOS 15.0, *) {
            Image(systemName: isCopied ? "checkmark.circle.fill" : "document.on.document")
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
                .font(.caption)
                .foregroundStyle(iconColor)
        } else {
            Image(systemName: isCopied ? "checkmark.circle.fill" : "document.on.document")
                .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                .font(.caption)
                .foregroundStyle(iconColor)
        }
    }

    private func copyEntry() {
        NSPasteboard.general.copyText(entry.formatted(dateFormatter: dateFormatter))
        withAnimation {
            isCopied = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation {
                isCopied = false
            }
        }
    }
}

#Preview {
    DiagnosticsSettingsTab(isMock: true)
        .frame(width: 600, height: 400)
}
