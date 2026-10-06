//
//  LogsSettingsTab+Toolbar.swift
//  AppLocker
//
//  Created by Doe Phương on 05/10/26.
//

import SwiftUI

extension LogsSettingsTab {
    @ToolbarContentBuilder
    var logsToolbarContent: some ToolbarContent {
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
                let iconName = collapseRepeatingLogs ? "square.stack.3d.up.fill" : "square.stack.3d.up"
                let image = Image(systemName: iconName)
                if #available(macOS 15.0, *) {
                    image.contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
                } else {
                    image.contentTransition(.symbolEffect(.replace.downUp.byLayer))
                }
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
            logStore.reload()
        }, label: {
            Label {
                Text("Refresh")
            } icon: {
                refreshIcon
            }
        })
        .help("Refresh logs")
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

    @ViewBuilder
    private var exportIcon: some View {
        let iconName = isExportSuccess ? "checkmark.circle" : "square.and.arrow.up"
        let image = Image(systemName: iconName)

        if #available(macOS 15.0, *) {
            image.contentTransition(
                .symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating.speed(1.3))
            )
        } else {
            image.contentTransition(
                .symbolEffect(.replace.downUp.byLayer, options: .nonRepeating.speed(1.3))
            )
        }
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
