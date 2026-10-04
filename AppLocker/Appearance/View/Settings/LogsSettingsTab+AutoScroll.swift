//
//  LogsSettingsTab+AutoScroll.swift
//  AppLocker
//
//  Created by Doe Phương on 03/10/26.
//

import SwiftUI

// MARK: - Search Focus

/// Binds the `.searchable` field focus on macOS 15+; no-op on earlier systems.
struct LogSearchFocusModifier: ViewModifier {
    let isFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.searchFocused(isFocused)
        } else {
            content
        }
    }
}

// MARK: - Drag Auto-Scroller

/// Tracks viewport geometry during a marquee drag and drives edge auto-scrolling,
/// mirroring AppKit's `autoscroll(with:)` behaviour in Finder.
@MainActor
final class LogDragAutoScroller {
    /// Distance from the top/bottom edge (pt) that triggers auto-scroll.
    static let edgeZone: CGFloat = 32
    /// Extra bottom zone covering the bottom status bar inset.
    static let bottomBarZone: CGFloat = 30
    static let tickInterval: Duration = .milliseconds(50)

    var viewportHeight: CGFloat = 0
    var contentOrigin: CGPoint = .zero
    private var startContentLocation: CGPoint?
    private var lastViewportLocation: CGPoint = .zero
    private var scrollTask: Task<Void, Never>?

    var visibleContentTop: CGFloat { -contentOrigin.y }
    var visibleContentBottom: CGFloat { visibleContentTop + viewportHeight }

    var dragStartInContent: CGPoint? { startContentLocation }
    var dragCurrentInContent: CGPoint { toContent(lastViewportLocation) }

    /// -1 = scroll up, 1 = scroll down, 0 = idle.
    var direction: Int {
        if lastViewportLocation.y < Self.edgeZone { return -1 }
        if lastViewportLocation.y > viewportHeight - Self.bottomBarZone - Self.edgeZone { return 1 }
        return 0
    }

    func track(start: CGPoint, current: CGPoint) {
        if startContentLocation == nil { startContentLocation = toContent(start) }
        lastViewportLocation = current
    }

    func startIfNeeded(step: @escaping @MainActor (Int) -> Void) {
        guard scrollTask == nil, direction != 0 else { return }
        scrollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let currentDirection = self.direction
                guard currentDirection != 0 else {
                    self.scrollTask = nil
                    return
                }
                step(currentDirection)
                try? await Task.sleep(for: Self.tickInterval)
            }
        }
    }

    func stop() {
        scrollTask?.cancel()
        scrollTask = nil
        startContentLocation = nil
    }

    private func toContent(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - contentOrigin.x, y: point.y - contentOrigin.y)
    }
}

// MARK: - Drag Gesture & Auto-Scroll Wiring

extension LogsSettingsTab {
    func logDragGesture(proxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("LogViewport"))
            .onChanged { value in
                if dragAutoScroller.dragStartInContent == nil { resignSearchFocus() }
                dragAutoScroller.track(start: value.startLocation, current: value.location)
                applyDragSelection()
                dragAutoScroller.startIfNeeded { direction in
                    autoScrollStep(direction, proxy: proxy)
                }
            }
            .onEnded { _ in
                dragAutoScroller.stop()
                selectionManager.handleDragEnded()
            }
    }

    /// Ends `.searchable` text editing when the user clicks into the log list.
    /// macOS 15+: native `.searchFocused(_:)` binding. macOS 14: resign the AppKit first responder.
    func resignSearchFocus() {
        if #available(macOS 15.0, *) {
            isSearchFocused = false
        } else {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    func applyDragSelection() {
        guard let start = dragAutoScroller.dragStartInContent else { return }
        selectionManager.handleDragChanged(
            startLocation: start,
            currentLocation: dragAutoScroller.dragCurrentInContent,
            entries: displayEntries,
            rowFrames: rowFrames
        )
    }

    /// Scrolls one row beyond the visible edge, then re-evaluates the selection
    /// so rows revealed by scrolling join the marquee even without mouse movement.
    private func autoScrollStep(_ direction: Int, proxy: ScrollViewProxy) {
        let entries = displayEntries
        if direction > 0 {
            autoScrollDown(entries: entries, proxy: proxy)
        } else {
            autoScrollUp(entries: entries, proxy: proxy)
        }
        applyDragSelection()
    }

    private func autoScrollDown(entries: [GroupedLogEntry], proxy: ScrollViewProxy) {
        let bottom = dragAutoScroller.visibleContentBottom
        if let next = entries.first(where: { (rowFrames[$0.id]?.maxY ?? 0) > bottom + 1 }) {
            proxy.scrollTo(next.id, anchor: .bottom)
        } else {
            proxy.scrollTo("log_bottom", anchor: .bottom)
        }
    }

    private func autoScrollUp(entries: [GroupedLogEntry], proxy: ScrollViewProxy) {
        let top = dragAutoScroller.visibleContentTop
        if let previous = entries.last(where: { (rowFrames[$0.id]?.minY ?? .infinity) < top - 1 }) {
            proxy.scrollTo(previous.id, anchor: .top)
        }
    }
}
