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

    // Backwards compatibility aliases for sheet layout
    struct AddApp {
        static let minSize = WindowLayout.addAppMinSize
        static let listMaxHeight = WindowLayout.addAppListMaxHeight
    }
    struct DeleteQueue {
        static let minSize = WindowLayout.deleteQueueMinSize
    }
    struct LockingPopup {
        static let minSize = WindowLayout.lockingPopupMinSize
    }
    struct BatchAuth {
        static let size = WindowLayout.batchAuthSize
        static let maxListHeight = WindowLayout.batchAuthMaxListHeight
    }
    struct About {
        static let size = WindowLayout.aboutSize
    }
    struct Main {
        static let size = WindowLayout.mainSize
    }
    struct Welcome {
        static let size = WindowLayout.welcomeSize
    }
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
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(in: Capsule())
        } else {
            content
                .background(
                    Capsule()
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
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
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            isSelected
                                ? Color(NSColor.controlBackgroundColor)
                                : Color(NSColor.controlBackgroundColor).opacity(0.35)
                        )
                )
        }
    }
}

extension View {
    func liquidGlassBackground(
        material: NSVisualEffectView.Material = .hudWindow
    ) -> some View {
        modifier(LiquidGlassBackgroundModifier(material: material))
    }

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
            let selector = NSSelectorFromString("performWindowDragWithEvent:")
            if let window = window, window.responds(to: selector) {
                window.perform(selector, with: event)
            }
        }
    }
}
