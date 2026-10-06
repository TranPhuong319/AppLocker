//
//  LogsSettingsTab+ContextMenu.swift
//  AppLocker
//
//  Created by Doe Phương on 03/10/26.
//

import SwiftUI

extension LogsSettingsTab {
    @ViewBuilder
    func bottomBar(proxy: ScrollViewProxy) -> some View {
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
                        proxy.scrollTo("log_bottom", anchor: .bottom)
                    }
                }, label: {
                    Label("Jump to bottom", systemImage: "arrow.down.to.line").font(.caption)
                })
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .transition(.opacity)
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
    func rowContextMenu(for item: GroupedLogEntry, index: Int) -> some View {
        Button {
            if selectionManager.hasSelection {
                selectionManager.copySelected(entries: displayEntries, dateFormatter: dateFormatter)
            } else {
                selectionManager.copySingleEntry(item.entry, dateFormatter: dateFormatter)
            }
        } label: {
            let count = selectionManager.selectedCount
            Label(count > 1 ? "Copy \(count) Selected Logs" : "Copy Log", systemImage: "doc.on.doc")
        }

        Divider()

        Button {
            selectionManager.selectAll(entries: displayEntries)
        } label: {
            Label("Select All", systemImage: "checklist")
        }

        if selectionManager.hasSelection {
            Button { selectionManager.deselectAll() } label: {
                Label("Deselect All", systemImage: "xmark.circle")
            }
        }
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
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading logs…").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func errorPlaceholder(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
            Text("Could not load logs").fontWeight(.medium)
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.page.slash").font(.title2).foregroundStyle(.secondary)
            Text("No log entries found").fontWeight(.medium).foregroundStyle(.secondary)
            Text("Try adjusting the time range or filters.").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drag Selection Helpers

    @ViewBuilder
    var dragSelectionOverlay: some View {
        if let rect = selectionManager.dragSelectionRect {
            Rectangle()
                .fill(Color(nsColor: .controlAccentColor).opacity(0.14))
                .overlay(
                    Rectangle()
                        .stroke(Color(nsColor: .controlAccentColor).opacity(0.5), lineWidth: 1)
                )
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Row Bounds Preference

struct LogRowBoundsPreference: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
