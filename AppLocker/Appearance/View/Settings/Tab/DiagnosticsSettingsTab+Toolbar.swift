//
//  DiagnosticsSettingsTab+Toolbar.swift
//  AppLocker
//
//  Created by Doe Phương on 05/10/26.
//

import SwiftUI

extension DiagnosticsSettingsTab {
    @ToolbarContentBuilder
    var diagnosticsToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            timeRangePicker
            processPicker
            levelPicker
            groupRepeatingToggle
            refreshButton
            clearLogsButton
            exportLogsButton
        }
    }

    // MARK: - Filter Pickers

    @ViewBuilder
    private var timeRangePicker: some View {
        Picker("Time Range", selection: $logStore.selectedTimeRange) {
            ForEach(LogTimeRange.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var processPicker: some View {
        Picker("Process", selection: $logStore.selectedSubsystem) {
            ForEach(LogSubsystemFilter.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var levelPicker: some View {
        Picker("Level", selection: $logStore.selectedLevel) {
            ForEach(LogLevelFilter.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
    }

    // MARK: - Toolbar Action Buttons

    @ViewBuilder
    private var groupRepeatingToggle: some View {
        Toggle(isOn: $collapseRepeatingLogs) {
            Label {
                Text("Group Repeating Logs")
            } icon: {
                Image(systemName: collapseRepeatingLogs ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                    .magicSymbolReplace()
            }
        }
        .toggleStyle(.button)
        .help(
            collapseRepeatingLogs ? Text("Group repeating logs (On)") : Text("Group repeating logs (Off)")
        )
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button(action: {
            refreshTrigger += 1
            guard !isMock else { return }
            #if DEBUG
            if NSEvent.modifierFlags.contains(.option) {
                logStore.stopPolling()
                logStore.entries = []
                logStore.filteredEntries = []
                logStore.groupedFilteredEntries = []
                logStore.errorMessage = "The operation couldn’t be completed. (OSLogStore error 1 - Access Denied)"
                return
            }
            #endif
            displayLimit = 500
            logStore.reload()
        }, label: {
            Label {
                Text("Refresh")
            } icon: {
                RefreshToolbarIcon(trigger: refreshTrigger)
            }
        })
        .help("Refresh logs")
    }

    @ViewBuilder
    private var clearLogsButton: some View {
        Button(action: { logStore.clearLogs() }, label: {
            Label("Clear", systemImage: "trash")
        })
        .disabled(logStore.entries.isEmpty)
        .help("Clear current logs")
    }

    @ViewBuilder
    private var exportLogsButton: some View {
        Button(action: {
            exportDocument = LogTextDocument(text: logStore.exportText(dateFormatter: dateFormatter))
            isExporting = true
        }, label: {
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

    private var exportIcon: some View {
        Image(systemName: isExportSuccess ? "checkmark.circle" : "square.and.arrow.up")
            .magicSymbolReplace(options: .nonRepeating.speed(1.3))
    }

    // MARK: - Export Helpers

    func handleExportSuccess() {
        resetExportTask?.cancel()
        resetExportTask = Task { @MainActor in
            withAnimation(.snappy(duration: 1)) {
                isExportSuccess = true
            }
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 1)) {
                isExportSuccess = false
            }
        }
    }

    var exportFilename: String {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        return "AppLocker-Logs-\(stamp)"
    }
}
