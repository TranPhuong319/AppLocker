//
//  BatchAuthView.swift
//  AppLocker
//
//  Created by Doe Phương on 31/7/26.
//

import SwiftUI
import AppKit

struct PendingAppItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let cdhash: String
    let pid: Int32
    var isSelected: Bool = true
}

struct BatchAuthView: View {
    @ObservedObject var server: XPCServer
    var onAuthenticate: () -> Void
    var onCancel: () -> Void

    var selectedCount: Int {
        server.pendingApps.filter { $0.isSelected }.count
    }

    var headerTitle: String {
        let count = server.pendingApps.count
        if count <= 1 {
            return String(localized: "Do you want to launch this application?")
        } else {
            return String(format: String(localized: "Do you want to launch these %d applications?"), count)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header inside View (balanced spacing for window titlebar area)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.blue)
                    
                    Text(headerTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(String(format: String(localized: "Automatically close the application after %d seconds"), server.remainingSeconds))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.top, 2)
            .padding(.bottom, 4)

            Divider()

            // List of pending applications
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($server.pendingApps) { $app in
                        BatchAppRowView(app: $app, icon: getAppIcon(for: app.path))
                    }
                }
            }
            .frame(maxHeight: WindowLayout.BatchAuth.maxListHeight)

            Divider()

            // Action Buttons
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    HStack {
                        Text(String(localized: "Cancel"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minWidth: 110)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button(action: onAuthenticate) {
                    HStack {
                        Image(systemName: "touchid")
                        Text(String(format: String(localized: "Authentication (%d)"), selectedCount))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedCount == 0)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: WindowLayout.BatchAuth.size.width)
        .background(
            ZStack {
                VisualEffectView(material: .windowBackground, blendingMode: .withinWindow)
                Color(NSColor.windowBackgroundColor).opacity(0.88)
            }
        )
    }

    private func getAppIcon(for path: String) -> NSImage? {
        return AppIconProvider.shared.icon(forPath: path, size: 40)
    }
}

struct BatchAppRowView: View {
    @Binding var app: PendingAppItem
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $app.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()

            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .opacity(app.isSelected ? 1.0 : 0.5)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .foregroundColor(app.isSelected ? .blue : .secondary)
                    .opacity(app.isSelected ? 1.0 : 0.5)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(app.isSelected ? .primary : .secondary)

                Text(app.path)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(app.isSelected ? 0.9 : 0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(app.isSelected ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(app.isSelected ? Color.blue.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                app.isSelected.toggle()
            }
        }
    }
}

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

#Preview {
    BatchAuthViewPreviewWrapper()
}

private struct BatchAuthViewPreviewWrapper: View {
    @StateObject private var server: XPCServer = {
        let xpcServer = XPCServer()
        xpcServer.pendingApps = [
            PendingAppItem(name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari", cdhash: "abc123hash", pid: 1024, isSelected: true),
            PendingAppItem(name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode", cdhash: "def456hash", pid: 2048, isSelected: true),
            PendingAppItem(name: "Telegram", path: "/Applications/Telegram.app/Contents/MacOS/Telegram", cdhash: "ghi789hash", pid: 4096, isSelected: false)
        ]
        xpcServer.remainingSeconds = 60
        return xpcServer
    }()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        BatchAuthView(
            server: server,
            onAuthenticate: {
                print("Mock Authenticate triggered for \(server.pendingApps.filter(\.isSelected).count) apps")
            },
            onCancel: {
                print("Mock Cancel triggered")
            }
        )
        .frame(width: WindowLayout.BatchAuth.size.width, height: WindowLayout.BatchAuth.size.height)
        .onReceive(timer) { _ in
            if server.remainingSeconds > 0 {
                server.remainingSeconds -= 1
            }
        }
    }
}
