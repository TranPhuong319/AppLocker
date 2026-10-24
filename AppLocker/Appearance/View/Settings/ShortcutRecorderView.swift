//
//  ShortcutRecorderView.swift
//  AppLocker
//
//  Created by Doe Phương on 24/10/26.
//

import Carbon
import SwiftUI

/// View ghi nhận và hiển thị phím tắt người dùng chọn (Shortcut Recorder)
struct ShortcutRecorderView: View {
    let shortcut: HotKeyShortcut?
    let onSave: (HotKeyShortcut?) -> Void

    @State private var isRecording: Bool = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            recordButton

            if shortcut != nil && !isRecording {
                clearButton
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var recordButton: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 4) {
                if isRecording {
                    Text("Type shortcut…")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(.body, design: .rounded))
                } else if let shortcut {
                    Text(shortcut.displayString)
                        .fontWeight(.medium)
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isRecording ? Color.accentColor : Color.primary.opacity(0.15),
                        lineWidth: isRecording ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var clearButton: some View {
        Button(action: {
            onSave(nil)
        }, label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
                .font(.system(size: 13))
        })
        .buttonStyle(.plain)
        .help(String(localized: "Clear shortcut"))
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            let validModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)) &&
                validModifiers.isEmpty {
                onSave(nil)
                stopRecording()
                return nil
            }

            guard validModifiers.contains(.command) ||
                  validModifiers.contains(.control) ||
                  validModifiers.contains(.option) else {
                NSSound.beep()
                return nil
            }

            guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
                return nil
            }

            let carbonMods = HotKeyShortcut.carbonModifiers(from: validModifiers)
            let newShortcut = HotKeyShortcut(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: carbonMods,
                characters: chars.lowercased()
            )
            onSave(newShortcut)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ShortcutRecorderView(shortcut: .defaultAppList) { _ in }
        ShortcutRecorderView(shortcut: nil) { _ in }
    }
    .padding()
}
