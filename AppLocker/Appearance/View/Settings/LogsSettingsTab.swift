//
//  LogsSettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 30/9/25.
//

import SwiftUI
import OSLog
import UniformTypeIdentifiers

// MARK: - Logs Settings Tab

struct LogsSettingsTab: View {
    let isMock: Bool

    @AppStorage("collapseRepeatingLogs") private var collapseRepeatingLogs: Bool = true
    @State private var logStore = LogStore()
    @State private var isExporting: Bool = false
    @State private var isExportSuccess: Bool = false
    @State private var resetExportTask: Task<Void, Never>?
    @State private var isAtBottom: Bool = true
    @State private var refreshTrigger: Int = 0

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private var displayEntries: [GroupedLogEntry] {
        collapseRepeatingLogs
            ? logStore.groupedEntries()
            : logStore.filteredEntries.map { GroupedLogEntry(entry: $0, count: 1) }
    }

    init(isMock: Bool = false) {
        self.isMock = isMock
    }

    var body: some View {
        logListContent
            .searchable(text: $logStore.searchText, prompt: "Search logs…")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("Time Range", selection: $logStore.selectedTimeRange) {
                        ForEach(LogTimeRange.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Picker("Process", selection: $logStore.selectedSubsystem) {
                        ForEach(LogSubsystemFilter.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Picker("Level", selection: $logStore.selectedLevel) {
                        ForEach(LogLevelFilter.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)

                    Button(action: {
                        withAnimation(.snappy(duration: 0.25)) { collapseRepeatingLogs.toggle() }
                    }, label: {
                        Label {
                            Text("Group Repeating Logs")
                        } icon: {
                            Image(systemName: collapseRepeatingLogs ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                                .foregroundStyle(
                                    collapseRepeatingLogs ? AnyShapeStyle(.tint) : AnyShapeStyle(.foreground)
                                )
                        }
                    })
                    .help(
                        collapseRepeatingLogs ? Text("Group repeating logs (On)") : Text("Group repeating logs (Off)")
                    )

                    Button(action: {
                        refreshTrigger += 1
                        guard !isMock else { return }
                        logStore.reload()
                    }, label: {
                        Label {
                            Text("Refresh")
                        } icon: {
                            if #available(macOS 15.0, *) {
                                Image(systemName: "arrow.clockwise")
                                    .symbolEffect(.rotate.byLayer, value: refreshTrigger)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .symbolEffect(.bounce.byLayer, value: refreshTrigger)
                            }
                        }
                    })
                    .help("Refresh logs")

                    Button(action: { logStore.clearLogs() }, label: {
                        Label("Clear", systemImage: "trash")
                    })
                    .disabled(logStore.entries.isEmpty)
                    .help("Clear current logs")

                    Button(action: { isExporting = true }, label: {
                        Label {
                            Text("Export")
                        } icon: {
                            exportIcon
                        }
                    })
                    .disabled(logStore.filteredEntries.isEmpty)
                    .help(
                        isExportSuccess
                            ? Text("Logs exported successfully")
                            : Text("Export visible logs to a .log file")
                    )
                }
            }
            .task {
                guard !isMock else { return }
                logStore.reload()
                var idleRounds = 0
                while !Task.isCancelled {
                    let delay = idleRounds > 2 ? 3000 : 1500
                    try? await Task.sleep(for: .milliseconds(delay))
                    guard !Task.isCancelled else { break }
                    let before = logStore.filteredEntries.count
                    await logStore.fetchLatest()
                    idleRounds = (logStore.filteredEntries.count == before) ? (idleRounds + 1) : 0
                }
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

    // MARK: - Log List Content

    @ViewBuilder
    private var logListContent: some View {
        if logStore.isLoading && logStore.entries.isEmpty {
            loadingPlaceholder
        } else if let error = logStore.errorMessage, logStore.entries.isEmpty {
            errorPlaceholder(error)
        } else if logStore.filteredEntries.isEmpty {
            emptyPlaceholder
        } else {
            logList
        }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayEntries) { item in
                        LogEntryRow(entry: item.entry, repeatCount: item.count, dateFormatter: dateFormatter)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .transition(.opacity)
                        Divider().padding(.leading, 20)
                    }
                }
                .background(ScrollBottomTracker { atBottom in
                    MainActor.assumeIsolated { isAtBottom = atBottom }
                })
                Color.clear.frame(height: 1).id("log_bottom")
            }
            .contentMargins(.trailing, 16, for: .scrollContent)
            .contentMargins(.top, 8, for: .scrollContent)
            .onChange(of: displayEntries.count) { _, _ in
                guard isAtBottom else { return }
                proxy.scrollTo("log_bottom", anchor: .bottom)
            }
            .task {
                try? await Task.sleep(for: .milliseconds(80))
                proxy.scrollTo("log_bottom", anchor: .bottom)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    statusText
                    Spacer()
                    if !isAtBottom {
                        Button(action: {
                            withAnimation { proxy.scrollTo("log_bottom", anchor: .bottom) }
                        }, label: {
                            Label("Jump to bottom", systemImage: "arrow.down.to.line")
                                .font(.caption)
                        })
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(.windowBackground)
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        let count = collapseRepeatingLogs ? displayEntries.count : logStore.filteredEntries.count
        let total = logStore.filteredEntries.count
        Text(collapseRepeatingLogs && count < total ? "\(count) events (\(total) total)" : "\(total) entries")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(count)))
            .animation(.snappy(duration: 0.25), value: count)
    }

    @ViewBuilder
    private var exportIcon: some View {
        let image = Image(systemName: isExportSuccess ? "checkmark.circle" : "square.and.arrow.up")
        if #available(macOS 15.0, *) {
            exportIconView(image, effect: .replace.magic(fallback: .downUp.byLayer))
        } else {
            exportIconView(image, effect: .replace.downUp.byLayer)
        }
    }

    private func handleExportSuccess() {
        resetExportTask?.cancel()
        resetExportTask = Task { @MainActor in
            isExportSuccess = true
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            isExportSuccess = false
        }
    }
}

// MARK: - Helpers & Placeholders

private extension LogsSettingsTab {
    var exportIconStyle: AnyShapeStyle {
        if isExportSuccess {
            return AnyShapeStyle(Color.green)
        }
        let color = logStore.filteredEntries.isEmpty
            ? Color(nsColor: .disabledControlTextColor)
            : Color(nsColor: .controlTextColor)
        return AnyShapeStyle(color)
    }

    func exportIconView(_ image: Image, effect: some ContentTransitionSymbolEffect & SymbolEffect) -> some View {
        image
            .contentTransition(.symbolEffect(effect, options: .nonRepeating.speed(1.3)))
            .foregroundStyle(exportIconStyle)
    }

    var exportFilename: String {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        return "AppLocker-Logs-\(stamp)"
    }

    var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading logs…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func errorPlaceholder(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
            Text("Could not load logs").fontWeight(.medium)
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.page.slash").font(.title2).foregroundStyle(.secondary)
            Text("No log entries found").fontWeight(.medium).foregroundStyle(.secondary)
            Text("Try adjusting the time range or filters.").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LogsSettingsTab(isMock: true)
        .frame(width: 600, height: 400)
}
