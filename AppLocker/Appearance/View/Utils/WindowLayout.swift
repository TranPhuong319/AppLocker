//
//  WindowLayout.swift
//  AppLocker
//
//  Created by Doe Phương on 16/2/26.
//

import AppKit
import Foundation
import SwiftUI

/// Single source of truth cho tất cả kích thước window và sheet trong app.
/// Khi cần thay đổi kích thước, chỉ cần sửa ở đây.
enum WindowLayout {
    static let mainSize = NSSize(width: 450, height: 470)
    static let welcomeSize = NSSize(width: 660, height: 480)
    static let addAppMinSize = NSSize(width: 400, height: 500)
    static let addAppListMaxHeight: CGFloat = 420
    static let deleteQueueMinSize = NSSize(width: 350, height: 370)
    static let missingAppsMinSize = NSSize(width: 380, height: 380)
    static let missingAppsListMaxHeight: CGFloat = 300
    static let lockingPopupMinSize = NSSize(width: 200, height: 100)
    static let batchAuthSize = NSSize(width: 440, height: 360)
    static let batchAuthMaxListHeight: CGFloat = 220
    static let aboutSize = NSSize(width: 450, height: 340)
    static let settingsMinSize = NSSize(width: 680, height: 460)
    static let settingsGeneralSize = NSSize(width: 680, height: 460)
    static let settingsSecuritySize = NSSize(width: 680, height: 460)
    static let settingsUpdatesSize = NSSize(width: 680, height: 460)
    static let settingsAppearanceSize = NSSize(width: 680, height: 460)
    static let settingsActivitySize = NSSize(width: 800, height: 500)
    static let settingsDiagnosticsSize = NSSize(width: 1100, height: 580)
    static let settingsLogsSize = settingsDiagnosticsSize
    static let settingsSize = settingsMinSize
}

// MARK: - Liquid Glass Visual Effects & Modifiers
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct LiquidGlassBackgroundModifier: ViewModifier {
    var material: NSVisualEffectView.Material

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(in: Rectangle())
        } else {
            content
                .background(
                    VisualEffectView(material: material, blendingMode: .behindWindow)
                )
        }
    }
}

struct LiquidGlassCapsuleModifier: ViewModifier {
    var isInteractive: Bool = true

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(isInteractive ? .regular.interactive() : .regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        }
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    var isSelected: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: 10))
        } else {
            content
                .background(
                    .ultraThinMaterial.opacity(isSelected ? 1.0 : 0.4),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(isSelected ? 0.15 : 0.05), lineWidth: 0.5)
                )
        }
    }
}

struct LiquidGlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        }
    }
}

struct LiquidGlassBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(in: Rectangle())
        } else {
            content
                .background(.bar)
        }
    }
}

struct LiquidGlassContainer<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    func liquidGlassBackground(
        material: NSVisualEffectView.Material = .hudWindow
    ) -> some View {
        modifier(LiquidGlassBackgroundModifier(material: material))
    }

    func liquidGlassCapsule(isInteractive: Bool = true) -> some View {
        modifier(LiquidGlassCapsuleModifier(isInteractive: isInteractive))
    }

    func liquidGlassCircle() -> some View {
        modifier(LiquidGlassCircleModifier())
    }

    func liquidGlassCard(isSelected: Bool = true) -> some View {
        modifier(LiquidGlassCardModifier(isSelected: isSelected))
    }

    func liquidGlassBar() -> some View {
        modifier(LiquidGlassBarModifier())
    }

    @ViewBuilder
    func softScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

// MARK: - Window Dragging Area Helper
struct WindowDragArea<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        return DragHostingView(rootView: content)
    }

    func updateNSView(_ nsView: NSHostingView<Content>, context: Context) {
        nsView.rootView = content
    }

    private class DragHostingView<V: View>: NSHostingView<V> {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - Synchronized Button Width Preference
struct EqualWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Scroll Bottom Tracker

final class TrackerNSView: NSView {
    var onMoveToWindow: (() -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            onMoveToWindow?()
        }
    }
}

struct ScrollBottomTracker: NSViewRepresentable {
    @Binding var isAtBottom: Bool
    var triggerScrollToBottom: Int = 0

    func makeNSView(context: Context) -> TrackerNSView {
        let view = TrackerNSView()
        context.coordinator.setup(view: view, isAtBottom: $isAtBottom)
        return view
    }

    func updateNSView(_ nsView: TrackerNSView, context: Context) {
        if context.coordinator.lastTrigger != triggerScrollToBottom {
            context.coordinator.lastTrigger = triggerScrollToBottom
            context.coordinator.scrollToBottom()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        private var token: (any NSObjectProtocol)?
        private weak var scrollView: NSScrollView?
        var lastTrigger: Int = 0
        private var isAtBottomBinding: Binding<Bool>?

        func setup(view: TrackerNSView, isAtBottom: Binding<Bool>) {
            self.isAtBottomBinding = isAtBottom
            view.onMoveToWindow = { [weak self, weak view] in
                DispatchQueue.main.async {
                    guard let self, let view else { return }
                    if let targetScrollView = ScrollBottomTracker.findScrollView(for: view) {
                        self.attach(to: targetScrollView)
                    }
                }
            }
        }

        func attach(to scrollView: NSScrollView) {
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            if let token { NotificationCenter.default.removeObserver(token) }
            token = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                MainActor.assumeIsolated {
                    guard let self, let scrollView else { return }
                    self.updateAtBottom(scrollView: scrollView)
                }
            }
            updateAtBottom(scrollView: scrollView)
        }

        private func updateAtBottom(scrollView: NSScrollView) {
            let docHeight = scrollView.documentView?.frame.height ?? 0
            let visibleMaxY = scrollView.contentView.bounds.maxY
            let atBottom = visibleMaxY >= docHeight - 35
            if isAtBottomBinding?.wrappedValue != atBottom {
                isAtBottomBinding?.wrappedValue = atBottom
            }
        }

        func scrollToBottom() {
            guard let scrollView else { return }
            if let tableView = scrollView.documentView as? NSTableView, tableView.numberOfRows > 0 {
                tableView.scrollRowToVisible(tableView.numberOfRows - 1)
            } else if let docView = scrollView.documentView {
                let targetY = max(0, docView.frame.height - scrollView.contentView.bounds.height)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        isolated deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }

    static func findScrollView(for view: NSView) -> NSScrollView? {
        if let targetScrollView = view.enclosingScrollView { return targetScrollView }
        var current: NSView? = view.superview
        while let candidateView = current {
            if let targetScrollView = searchSubviews(in: candidateView, excluding: view) { return targetScrollView }
            current = candidateView.superview
        }
        return nil
    }

    private static func searchSubviews(in parent: NSView, excluding: NSView) -> NSScrollView? {
        if let targetScrollView = parent as? NSScrollView { return targetScrollView }
        for subview in parent.subviews where subview !== excluding {
            if let targetScrollView = subview as? NSScrollView { return targetScrollView }
            if let found = searchSubviews(in: subview, excluding: excluding) { return found }
        }
        return nil
    }
}
