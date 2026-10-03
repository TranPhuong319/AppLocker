//
//  LogEntryRow.swift
//  AppLocker
//
//  Created by Doe Phương on 30/9/25.
//

import SwiftUI
import AppKit

struct LogEntryRow: View {
    let entry: AppLogEntry
    var repeatCount: Int = 1
    let dateFormatter: DateFormatter
    var isSelected: Bool = false

    @State private var isCopied: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            levelDot
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(dateFormatter.string(from: entry.date))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    subsystemBadge
                    categoryBadge

                    if repeatCount > 1 {
                        repeatBadge
                    }
                }

                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button(action: copyEntry, label: {
                copyIcon
            })
            .buttonStyle(.plain)
            .help("Copy entry")
            .accessibilityLabel("Copy log entry")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isSelected ? Color(nsColor: .controlAccentColor).opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var copyIcon: some View {
        if #available(macOS 15.0, *) {
            Image(systemName: isCopied ? "checkmark.circle" : "document.on.document")
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
                .font(.caption)
                .foregroundStyle(isCopied ? .green : .secondary)
        } else {
            Image(systemName: isCopied ? "checkmark.circle" : "document.on.document")
                .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                .font(.caption)
                .foregroundStyle(isCopied ? .green : .secondary)
        }
    }

    private var levelDot: some View {
        Circle().fill(levelColor)
    }

    private var levelColor: Color {
        switch entry.level {
        case .fault: return .red
        case .error: return .orange
        case .notice: return .yellow
        case .info: return .blue
        default: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var subsystemBadge: some View {
        Text(entry.subsystemShort)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 3))
    }

    private var categoryBadge: some View {
        Text(entry.category)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Color(nsColor: .controlAccentColor))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Color(nsColor: .controlAccentColor).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 3)
            )
    }

    private var repeatBadge: some View {
        Text("×\(repeatCount)")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor))
            )
            .contentTransition(.numericText(value: Double(repeatCount)))
    }

    private func copyEntry() {
        NSPasteboard.general.clearContents()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        NSPasteboard.general.setString(
            entry.formatted(dateFormatter: formatter),
            forType: .string
        )
        withAnimation {
            isCopied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                withAnimation {
                    isCopied = false
                }
            }
        }
    }
}
