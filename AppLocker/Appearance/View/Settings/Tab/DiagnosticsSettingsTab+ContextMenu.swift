//
//  DiagnosticsSettingsTab+ContextMenu.swift
//  AppLocker
//
//  Created by Doe Phương on 03/10/26.
//

import SwiftUI

extension DiagnosticsSettingsTab {
    @ViewBuilder
    var bottomBar: some View {
        HStack(spacing: 8) {
            statusText
            if selectionManager.hasSelection {
                Divider().frame(height: 12)
                selectionStatus
            }
            Spacer()
            if !isAtBottom {
                Button(action: {
                    withAnimation(.snappy(duration: 0.25)) {
                        isAtBottom = true
                        scrollToBottomTrigger += 1
                    }
                }, label: {
                    Label("Jump to bottom", systemImage: "arrow.down.to.line").font(.caption)
                })
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .transition(.opacity)
                .help("Jump to bottom")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(.windowBackground)
    }

    @ViewBuilder
    var selectionStatus: some View {
        HStack(spacing: 6) {
            Text("\(selectionManager.selectedCount) selected")
                .font(.caption)
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .fontWeight(.medium)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(selectionManager.selectedCount)))
                .animation(.snappy(duration: 0.25), value: selectionManager.selectedCount)

            Button(action: {
                selectionManager.copySelected(entries: displayEntries, dateFormatter: dateFormatter)
            }, label: {
                HStack(spacing: 4) {
                    copyStatusIcon
                    Text(selectionManager.isCopiedFeedback ? "Copied" : "Copy Selected")
                }
                .font(.caption)
            })
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("Copy selected log entries")

            Button(action: { selectionManager.deselectAll() }, label: {
                Text("Deselect").font(.caption)
            })
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Clear selection")
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    @ViewBuilder
    var copyStatusIcon: some View {
        let isCopied = selectionManager.isCopiedFeedback
        let image = Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
        if #available(macOS 15.0, *) {
            image.contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
        } else {
            image.contentTransition(.symbolEffect(.replace.downUp.byLayer))
        }
    }

    @ViewBuilder
    var keyboardShortcutsLayer: some View {
        Group {
            Button("Copy Selection") {
                selectionManager.copySelected(entries: displayEntries, dateFormatter: dateFormatter)
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(!selectionManager.hasSelection)

            Button("Select All Logs") {
                selectionManager.selectAll(entries: displayEntries)
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(displayEntries.isEmpty)

            Button("Deselect Logs") {
                selectionManager.deselectAll()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(!selectionManager.hasSelection)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    @ViewBuilder
    var statusText: some View {
        let count = collapseRepeatingLogs ? displayEntries.count : logStore.filteredEntries.count
        let total = logStore.filteredEntries.count
        Text(collapseRepeatingLogs && count < total ? "\(count) events (\(total) total)" : "\(total) entries")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(count)))
            .animation(.snappy(duration: 0.25), value: count)
    }

    var loadingPlaceholder: some View {
        ContentUnavailableView {
            ProgressView()
                .controlSize(.regular)
                .padding(.bottom, 2)
            Text("Loading logs…")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func errorPlaceholder(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Could not load logs", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(message)
        } actions: {
            Button("Reload Logs") {
                logStore.startPolling()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyPlaceholder: some View {
        ContentUnavailableView(
            "No log entries found",
            systemImage: "text.page.slash",
            description: Text("Try adjusting the time range or filters.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    var diagnosticsTableView: some View {
        Table(displayEntries, selection: $selectionManager.selectedIDs) {
            TableColumn("Time") { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.entry.resolvedLevel.color)
                        .frame(width: 6, height: 6)
                    Text(dateFormatter.string(from: item.entry.date))
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .width(min: 145, ideal: 155, max: 170)

            TableColumn("Level") { item in
                Text(item.entry.resolvedLevel.shortTag)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .width(min: 45, ideal: 50, max: 60)

            TableColumn("Process") { item in
                Text(item.entry.subsystemShort)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
            }
            .width(min: 80, ideal: 100, max: 130)

            TableColumn("Category") { item in
                Text(item.entry.category)
                    .font(.system(.caption, design: .monospaced))
            }
            .width(min: 70, ideal: 90, max: 130)

            TableColumn("Message") { item in
                HStack(spacing: 6) {
                    Text(item.entry.message)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if item.count > 1 {
                        Text("×\(item.count)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor)))
                    }
                    Spacer()
                    LogRowCopyButton(entry: item.entry, dateFormatter: dateFormatter)
                }
            }
        }
        .defaultScrollAnchor(.bottom)
        .background(ScrollBottomTracker(
            isAtBottom: $isAtBottom,
            triggerScrollToBottom: scrollToBottomTrigger
        ))
        .onChange(of: displayEntries.count) { _, _ in
            guard isAtBottom, !selectionManager.hasSelection else { return }
            scrollToBottomTrigger += 1
        }
        .onChange(of: logStore.filteredEntries.count) { _, _ in
            guard isAtBottom, !selectionManager.hasSelection else { return }
            scrollToBottomTrigger += 1
        }
        .onChange(of: refreshTrigger) { _, _ in
            scrollToBottomTrigger += 1
        }
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            scrollToBottomTrigger += 1
        }
        .contextMenu(forSelectionType: UUID.self) { selectedIDs in
            let targetIDs = selectedIDs.isEmpty ? selectionManager.selectedIDs : selectedIDs
            Button {
                let selected = displayEntries.filter { targetIDs.contains($0.id) }
                let text = selected
                    .map { $0.entry.formatted(dateFormatter: dateFormatter) }
                    .joined(separator: "\n")
                guard !text.isEmpty else { return }
                NSPasteboard.general.copyText(text)
            } label: {
                let count = targetIDs.count
                Label(count > 1 ? "Copy \(count) Selected Logs" : "Copy Log", systemImage: "doc.on.doc")
            }

            if targetIDs.count == 1,
               let firstID = targetIDs.first,
               let targetEntry = displayEntries.first(where: { $0.id == firstID }) {
                Button {
                    NSPasteboard.general.copyText(targetEntry.entry.message)
                } label: {
                    Label("Copy Message Only", systemImage: "text.quote")
                }
            }

            Divider()

            Button {
                selectionManager.selectAll(entries: displayEntries)
            } label: {
                Label("Select All", systemImage: "checklist")
            }

            if !targetIDs.isEmpty {
                Button {
                    selectionManager.deselectAll()
                } label: {
                    Label("Deselect All", systemImage: "xmark.circle")
                }
            }
        } primaryAction: { selectedIDs in
            let targetIDs = selectedIDs.isEmpty ? selectionManager.selectedIDs : selectedIDs
            let selected = displayEntries.filter { targetIDs.contains($0.id) }
            let text = selected
                .map { $0.entry.formatted(dateFormatter: dateFormatter) }
                .joined(separator: "\n")
            guard !text.isEmpty else { return }
            NSPasteboard.general.copyText(text)
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .background {
            keyboardShortcutsLayer
        }
    }
}
