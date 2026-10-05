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

    @AppStorage("collapseRepeatingLogs") var collapseRepeatingLogs: Bool = true
    @AppStorage("logsSelectedTimeRange") var storedTimeRange: LogTimeRange = .currentSession
    @AppStorage("logsSelectedSubsystem") var storedSubsystem: LogSubsystemFilter = .all
    @AppStorage("logsSelectedLevel") var storedLevel: LogLevelFilter = .all
    @State var logStore = LogStore()
    @State var selectionManager = LogSelectionManager()
    @State var isExporting: Bool = false
    @State var isExportSuccess: Bool = false
    @State var resetExportTask: Task<Void, Never>?
    @State var isAtBottom: Bool = true
    @State var refreshTrigger: Int = 0
    @State var rowFrames: [UUID: CGRect] = [:]
    @State var dragAutoScroller = LogDragAutoScroller()
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
        logListContent
            .searchable(text: $logStore.searchText, prompt: "Search logs…")
            .modifier(LogSearchFocusModifier(isFocused: $isSearchFocused))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("Time Range", selection: $logStore.selectedTimeRange) {
                        ForEach(LogTimeRange.allCases) { Text($0.displayName).tag($0) }
                    }.pickerStyle(.menu)
                    Picker("Process", selection: $logStore.selectedSubsystem) {
                        ForEach(LogSubsystemFilter.allCases) { Text($0.displayName).tag($0) }
                    }.pickerStyle(.menu)
                    Picker("Level", selection: $logStore.selectedLevel) {
                        ForEach(LogLevelFilter.allCases) { Text($0.displayName).tag($0) }
                    }.pickerStyle(.menu)

                    Button(action: {
                        withAnimation(.snappy(duration: 0.25)) { collapseRepeatingLogs.toggle() }
                    }, label: {
                        Label { Text("Group Repeating Logs") } icon: { groupRepeatingIcon }
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
                        Label { Text("Clear") } icon: { clearIcon }
                    })
                    .disabled(logStore.entries.isEmpty)
                    .help("Clear current logs")

                    Button(action: { isExporting = true }, label: {
                        Label { Text("Export") } icon: { exportIcon }
                    })
                    .disabled(logStore.filteredEntries.isEmpty)
                    .help(
                        isExportSuccess
                            ? Text("Logs exported successfully")
                            : Text("Export visible logs to a .log file")
                    )
                }
            }
            .onAppear {
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
                VStack(spacing: 0) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(displayEntries.enumerated()), id: \.element.id) { index, item in
                            LogEntryRow(
                                entry: item.entry,
                                repeatCount: item.count,
                                dateFormatter: dateFormatter,
                                isSelected: selectionManager.isSelected(item.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                resignSearchFocus()
                                selectionManager.handleRowClick(item: item, index: index, entries: displayEntries)
                            }
                            .contextMenu {
                                rowContextMenu(for: item, index: index)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .background(
                                GeometryReader { rowGeo in
                                    Color.clear.preference(
                                        key: LogRowBoundsPreference.self,
                                        value: [item.id: rowGeo.frame(in: .named("LogScrollContent"))]
                                    )
                                }
                            )
                            .transition(.opacity)
                            Divider().padding(.leading, 20)
                        }
                    }
                    .background(ScrollBottomTracker { atBottom in
                        MainActor.assumeIsolated { isAtBottom = atBottom }
                    })

                    Color.clear.frame(height: 1).id("log_bottom")
                }
                .coordinateSpace(name: "LogScrollContent")
                .onGeometryChange(for: CGPoint.self) { geo in
                    geo.frame(in: .named("LogViewport")).origin
                } action: { origin in
                    dragAutoScroller.contentOrigin = origin
                }
                .overlay(alignment: .topLeading) {
                    dragSelectionOverlay
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(.trailing, 16, for: .scrollContent)
            .contentMargins(.top, 8, for: .scrollContent)
            .contentShape(Rectangle())
            .onTapGesture {
                resignSearchFocus()
                selectionManager.deselectAll()
            }
            .onPreferenceChange(LogRowBoundsPreference.self) { newFrames in
                rowFrames = newFrames
            }
            .simultaneousGesture(logDragGesture(proxy: proxy))
            .coordinateSpace(name: "LogViewport")
            .onGeometryChange(for: CGFloat.self) { geo in
                geo.size.height
            } action: { height in
                dragAutoScroller.viewportHeight = height
            }
            .onChange(of: displayEntries.count) { _, _ in
                guard isAtBottom else { return }
                proxy.scrollTo("log_bottom", anchor: .bottom)
            }
            .onChange(of: displayEntries.map(\.id)) { _, newIDs in
                selectionManager.pruneInvalidSelection(validIDs: Set(newIDs))
            }
            .task {
                try? await Task.sleep(for: .milliseconds(80))
                proxy.scrollTo("log_bottom", anchor: .bottom)
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar(proxy: proxy)
            }
            .background {
                keyboardShortcutsLayer
            }
        }
    }
}

#Preview {
    LogsSettingsTab(isMock: true)
        .frame(width: 600, height: 400)
}
