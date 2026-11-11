//
//  ActivityRowView.swift
//  AppLocker
//
//  Created by Doe Phương on 27/10/26.
//

import AppKit
import SwiftUI

// MARK: - Activity Row View

struct ActivityRowView: View {
    let item: SecurityActivityItem
    var currentDate: Date = Date()
    let dateFormatter: DateFormatter
    let relativeFormatter: RelativeDateTimeFormatter

    @State private var isCopied: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    titleText
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    if item.repeatCount > 1 {
                        repeatBadge
                    }
                }

                subtitleText
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(dateFormatter.string(from: item.date))
            }

            Spacer()

            Button(action: copyEntry) {
                copyIcon
            }
            .buttonStyle(.plain)
            .help("Copy entry")
            .accessibilityLabel("Copy activity entry")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(item.type.symbolColor.opacity(isHovered ? 0.08 : 0.03))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isHovered
                        ? item.type.symbolColor.opacity(0.35)
                        : Color(nsColor: .separatorColor).opacity(0.6),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                copyEntry()
            } label: {
                Label("Copy Info", systemImage: "doc.on.doc")
            }

            if let path = item.resolvedIconPath {
                Button {
                    revealInFinder(path: path)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            mainAppIcon
                .frame(width: 36, height: 36)

            statusBadge
                .offset(x: 2, y: 2)
        }
        .frame(width: 36, height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.type.rawValue)
    }

    @ViewBuilder
    private var mainAppIcon: some View {
        if let path = item.resolvedIconPath {
            AppIconView(path: path, size: 36)
        } else {
            defaultPlaceholderIcon
        }
    }

    private var defaultPlaceholderIcon: some View {
        Image(nsImage: AppIconProvider.shared.defaultPlaceholder(size: 36))
            .resizable()
            .scaledToFit()
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var statusBadge: some View {
        ZStack {
            Circle()
                .fill(item.type.symbolColor)

            badgeIcon
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 16, height: 16)
        .overlay(
            Circle()
                .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var badgeIcon: some View {
        switch item.type {
        case .approved:
            Image(systemName: "checkmark")
        case .rejected:
            Image(systemName: "hand.raised.fill")
        case .tamperBlocked:
            Image(systemName: "exclamationmark")
        }
    }

    @ViewBuilder
    private var titleText: some View {
        switch item.type {
        case .approved:
            Text("Allowed Launch: \(item.targetAppName)")
        case .rejected:
            Text("Access Denied: \(item.targetAppName)")
        case .tamperBlocked:
            let senderDisplay = formatSender(name: item.senderName, pid: item.senderPid)
            Text("Anti-Tamper Shield: \(senderDisplay)")
        }
    }

    @ViewBuilder
    private var subtitleText: some View {
        let relTime = relativeFormatter.localizedString(for: item.date, relativeTo: currentDate)
        let pidDisplay = String(item.targetPid)
        if item.type == .tamperBlocked {
            if item.targetAppName == "Config" {
                switch item.tamperAction {
                case "Delete":
                    Text("Blocked deleting Config • \(relTime)")
                case "Rename":
                    Text("Blocked renaming Config • \(relTime)")
                case "Truncate":
                    Text("Blocked truncating Config • \(relTime)")
                case "Write":
                    Text("Blocked writing to Config • \(relTime)")
                default:
                    Text("Blocked modifying Config • \(relTime)")
                }
            } else {
                let targetDisplay = "\(item.targetAppName) (PID \(item.targetPid))"
                Text("Blocked signal to \(targetDisplay) • \(relTime)")
            }
        } else if item.type == .rejected, let reason = item.denialReason {
            switch reason {
            case .timedOut:
                Text("Timed out • PID \(pidDisplay) • \(relTime)")
            case .userCancelled:
                Text("Cancelled • PID \(pidDisplay) • \(relTime)")
            }
        } else {
            Text("PID \(pidDisplay) • \(relTime)")
        }
    }
}

// MARK: - Formatters & Actions

private extension ActivityRowView {

    func formatSender(name: String?, pid: Int32?) -> String {
        if let name = name {
            let pidStr = pid.map { " (PID \($0))" } ?? ""
            return "\(name)\(pidStr)"
        } else if let pid = pid {
            return "PID \(pid)"
        } else {
            return "Unknown"
        }
    }

    var repeatBadge: some View {
        repeatBadgeText
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(item.type.symbolColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(item.type.symbolColor.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    var repeatBadgeText: some View {
        switch item.type {
        case .tamperBlocked:
            Text("Attempted to tamper \(item.repeatCount) times")
        case .rejected:
            Text("Attempted to open \(item.repeatCount) times")
        case .approved:
            Text("Opened \(item.repeatCount) times")
        }
    }

    @ViewBuilder
    var copyIcon: some View {
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

    func copyEntry() {
        let text = item.clipboardFormattedText(dateFormatter: dateFormatter)
        NSPasteboard.general.copyText(text)

        withAnimation(.snappy(duration: 0.2)) {
            isCopied = true
        }

        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.8))
            } catch is CancellationError {
                return
            } catch {
                Logfile.app.warning(
                    "[ActivityRow] Copy timer interrupted: \(error.localizedDescription, privacy: .public)"
                )
                return
            }
            withAnimation(.snappy(duration: 0.2)) {
                isCopied = false
            }
        }
    }

    func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path).enclosingAppBundleURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
