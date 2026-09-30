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

    @State private var logStore = LogStore()
    @State private var isExporting: Bool = false
    @State private var isAtBottom: Bool = true

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    init(isMock: Bool = false) {
        self.isMock = isMock
    }

    var body: some View {
        logListContent
            .searchable(text: $logStore.searchText, prompt: "Search logs…")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("Time Range", selection: $logStore.selectedTimeRange) {
                        ForEach(LogTimeRange.allCases) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Process", selection: $logStore.selectedSubsystem) {
                        ForEach(LogSubsystemFilter.allCases) { sub in
                            Text(sub.displayName).tag(sub)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Level", selection: $logStore.selectedLevel) {
                        ForEach(LogLevelFilter.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.menu)

                    Button(action: {
                        guard !isMock else { return }
                        logStore.reload()
                    }, label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    })
                    .help("Refresh logs")

                    Button(action: {
                        logStore.clearLogs()
                    }, label: {
                        Label("Clear", systemImage: "trash")
                    })
                    .disabled(logStore.entries.isEmpty)
                    .help("Clear current logs")

                    Button(action: { isExporting = true }, label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    })
                    .disabled(logStore.filteredEntries.isEmpty)
                    .help("Export visible logs to a .log file")
                }
            }
            .task {
                guard !isMock else { return }
                logStore.reload()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(800))
                    guard !Task.isCancelled else { break }
                    await logStore.fetchLatest()
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: LogTextDocument(text: logStore.exportText(dateFormatter: dateFormatter)),
                contentType: LogTextDocument.logContentType,
                defaultFilename: exportFilename
            ) { _ in }
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
                    ForEach(logStore.filteredEntries) { entry in
                        LogEntryRow(entry: entry, dateFormatter: dateFormatter)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
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
            .onChange(of: logStore.filteredEntries.count) { _, _ in
                guard isAtBottom else { return }
                proxy.scrollTo("log_bottom", anchor: .bottom)
            }
            .task {
                try? await Task.sleep(for: .milliseconds(80))
                proxy.scrollTo("log_bottom", anchor: .bottom)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("\(logStore.filteredEntries.count) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading logs…")
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
            Text("Could not load logs")
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
            Image(systemName: "text.page.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No log entries found")
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text("Try adjusting the time range or filters.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var exportFilename: String {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        return "AppLocker-Logs-\(stamp)"
    }
}

// MARK: - Export Document

struct LogTextDocument: FileDocument {
    static let logContentType = UTType(filenameExtension: "log", conformingTo: .plainText) ?? .plainText
    static let readableContentTypes: [UTType] = [logContentType, .plainText]
    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// MARK: - Scroll Bottom Tracker

private struct ScrollBottomTracker: NSViewRepresentable {
    var onAtBottomChanged: @Sendable (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else { return }
            context.coordinator.attach(to: scrollView, notify: onAtBottomChanged)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        nonisolated(unsafe) private var token: NSObjectProtocol?

        func attach(to scrollView: NSScrollView, notify: @escaping @Sendable (Bool) -> Void) {
            token = NotificationCenter.default.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak scrollView] _ in
                MainActor.assumeIsolated {
                    guard let scrollView else { return }
                    let docHeight = scrollView.documentView?.frame.height ?? 0
                    let visibleMaxY = scrollView.contentView.bounds.maxY
                    notify(visibleMaxY >= docHeight - 40)
                }
            }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}

#Preview {
    LogsSettingsTab(isMock: true)
        .frame(width: 600, height: 400)
}
