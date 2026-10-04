//
//  LogSelectionManager.swift
//  AppLocker
//
//  Created by AppLocker
//

import SwiftUI
import AppKit
import Foundation

// MARK: - Log Selection Manager

@Observable
@MainActor
final class LogSelectionManager {
    var selectedIDs: Set<UUID> = []
    var lastSelectedIndex: Int?
    var isCopiedFeedback: Bool = false
    private var feedbackTask: Task<Void, Never>?

    var isDragging: Bool = false
    var dragSelectionRect: CGRect?
    private var initialSelectionBeforeDrag: Set<UUID> = []

    var hasSelection: Bool {
        !selectedIDs.isEmpty
    }

    var selectedCount: Int {
        selectedIDs.count
    }

    func isSelected(_ id: UUID) -> Bool {
        selectedIDs.contains(id)
    }

    func handleDragStart() {
        if !isDragging {
            isDragging = true
            initialSelectionBeforeDrag = selectedIDs
        }
    }

    func handleDragChanged(
        startLocation: CGPoint,
        currentLocation: CGPoint,
        entries: [GroupedLogEntry],
        rowFrames: [UUID: CGRect]
    ) {
        handleDragStart()

        let rect = CGRect(
            x: min(startLocation.x, currentLocation.x),
            y: min(startLocation.y, currentLocation.y),
            width: max(abs(currentLocation.x - startLocation.x), 1),
            height: max(abs(currentLocation.y - startLocation.y), 1)
        )
        dragSelectionRect = rect

        let isCommandHeld = NSEvent.modifierFlags.contains(.command)
        let isShiftHeld = NSEvent.modifierFlags.contains(.shift)

        let intersectingIndices = entries.enumerated().compactMap { index, item -> Int? in
            guard let frame = rowFrames[item.id] else { return nil }
            return (frame.minY <= rect.maxY && frame.maxY >= rect.minY) ? index : nil
        }

        guard let minIdx = intersectingIndices.min(), let maxIdx = intersectingIndices.max() else {
            if !isCommandHeld { selectedIDs.removeAll() }
            return
        }

        let draggedIDs = Set(entries[minIdx...maxIdx].map(\.id))

        if isCommandHeld {
            selectedIDs = initialSelectionBeforeDrag.union(draggedIDs)
        } else if isShiftHeld, let anchor = lastSelectedIndex, anchor < entries.count {
            let start = min(anchor, minIdx)
            let end = max(anchor, maxIdx)
            selectedIDs = Set(entries[start...end].map(\.id))
        } else {
            selectedIDs = draggedIDs
            lastSelectedIndex = minIdx
        }
    }

    func handleDragEnded() {
        isDragging = false
        dragSelectionRect = nil
        initialSelectionBeforeDrag.removeAll()
    }

    func handleRowClick(
        item: GroupedLogEntry,
        index: Int,
        entries: [GroupedLogEntry]
    ) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            toggleSelection(item.id, index: index)
        } else if modifiers.contains(.shift), let anchor = lastSelectedIndex, anchor < entries.count {
            let start = min(anchor, index)
            let end = max(anchor, index)
            let rangeIDs = entries[start...end].map(\.id)
            selectedIDs.formUnion(rangeIDs)
        } else {
            selectedIDs = [item.id]
            lastSelectedIndex = index
        }
    }

    private func toggleSelection(_ id: UUID, index: Int) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
            lastSelectedIndex = index
        }
    }

    func handleRowRightClick(item: GroupedLogEntry, index: Int) {
        if !selectedIDs.contains(item.id) {
            selectedIDs = [item.id]
            lastSelectedIndex = index
        }
    }

    func selectAll(entries: [GroupedLogEntry]) {
        selectedIDs = Set(entries.map(\.id))
    }

    func deselectAll() {
        selectedIDs.removeAll()
        lastSelectedIndex = nil
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

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        triggerCopiedFeedback()
    }

    func copySingleEntry(
        _ entry: AppLogEntry,
        dateFormatter: DateFormatter
    ) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            entry.formatted(dateFormatter: dateFormatter),
            forType: .string
        )
    }

    func pruneInvalidSelection(validIDs: Set<UUID>) {
        if !selectedIDs.isSubset(of: validIDs) {
            selectedIDs.formIntersection(validIDs)
        }
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
