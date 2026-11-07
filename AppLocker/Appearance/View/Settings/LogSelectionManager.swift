//
//  LogSelectionManager.swift
//  AppLocker
//
//  Created by Doe Phương on 1/10/26.
//

import SwiftUI
import AppKit
import Foundation

// MARK: - Log Selection Manager

@Observable
@MainActor
final class LogSelectionManager {
    var selectedIDs: Set<UUID> = []
    var isCopiedFeedback: Bool = false
    private var feedbackTask: Task<Void, Never>?

    var hasSelection: Bool {
        !selectedIDs.isEmpty
    }

    var selectedCount: Int {
        selectedIDs.count
    }

    func selectAll(entries: [GroupedLogEntry]) {
        selectedIDs = Set(entries.map(\.id))
    }

    func deselectAll() {
        selectedIDs.removeAll()
    }

    func copySelected(
        entries: [GroupedLogEntry],
        dateFormatter: DateFormatter
    ) {
        guard !selectedIDs.isEmpty else { return }
        let selected = entries.filter { selectedIDs.contains($0.id) }
        let text = selected
            .map { $0.entry.formatted(dateFormatter: dateFormatter) }
            .joined(separator: "\n")

        NSPasteboard.general.copyText(text)
        triggerCopiedFeedback()
    }

    private func triggerCopiedFeedback() {
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor in
            withAnimation(.snappy(duration: 0.25)) {
                self.isCopiedFeedback = true
            }
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.25)) {
                self.isCopiedFeedback = false
            }
        }
    }
}
