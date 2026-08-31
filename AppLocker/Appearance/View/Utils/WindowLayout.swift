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
    static let lockingPopupMinSize = NSSize(width: 200, height: 100)
    static let batchAuthSize = NSSize(width: 440, height: 360)
    static let batchAuthMaxListHeight: CGFloat = 220
    static let aboutSize = NSSize(width: 450, height: 248)
}

// MARK: - Liquid Glass Visual Effects & Modifiers
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

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

struct LiquidGlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(Color(NSColor.controlBackgroundColor))
            )
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    var isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isSelected
                            ? Color(NSColor.controlBackgroundColor)
                            : Color(NSColor.controlBackgroundColor).opacity(0.35)
                    )
            )
    }
}

extension View {
    func liquidGlassCapsule() -> some View {
        modifier(LiquidGlassCapsuleModifier())
    }

    func liquidGlassCard(isSelected: Bool = true) -> some View {
        modifier(LiquidGlassCardModifier(isSelected: isSelected))
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
