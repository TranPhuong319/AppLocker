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
    @Bindable var server: XPCServer
    var onAuthenticate: () -> Void
    var onCancel: () -> Void
    @State private var maxButtonWidth: CGFloat?

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

    var authButtonTitle: String {
        if selectedCount == 0 {
            return String(localized: "Authentication")
        } else {
            return String(format: String(localized: "Authentication (%d)"), selectedCount)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                topHeaderView

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach($server.pendingApps) { $app in
                            BatchAppRowView(app: $app, icon: appIcon(for: app.path))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .clipped()

                bottomActionBar
            }
            .padding(.top, -10)
            .background(
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            )
            .navigationTitle("Authentication")
            .toolbar {
                // Empty toolbar for Liquid Glass bridging without bordered pill item
            }
        }
        .frame(width: WindowLayout.batchAuthSize.width, height: WindowLayout.batchAuthSize.height)
    }

    @ViewBuilder
    private var topHeaderView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)

                Text(headerTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(
                String(
                    format: String(localized: "Automatically close the application after %d seconds"),
                    server.remainingSeconds
                )
            )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(server.remainingSeconds)))
                .animation(.snappy(duration: 0.3), value: server.remainingSeconds)
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button(
                action: onCancel,
                label: {
                    Text(String(localized: "Cancel"))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: EqualWidthKey.self, value: geo.size.width)
                            }
                        )
                        .frame(minWidth: maxButtonWidth)
                }
            )
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button(
                action: onAuthenticate,
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "touchid")
                        Text(authButtonTitle)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(selectedCount)))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: EqualWidthKey.self, value: geo.size.width)
                        }
                    )
                    .frame(minWidth: maxButtonWidth)
                }
            )
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedCount == 0)
            .animation(.snappy(duration: 0.25), value: selectedCount)
            .keyboardShortcut(.defaultAction)
        }
        .onPreferenceChange(EqualWidthKey.self) { width in
            if width > 0 {
                self.maxButtonWidth = max(self.maxButtonWidth ?? 0, width)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    private func appIcon(for path: String) -> NSImage? {
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
                    .foregroundStyle(app.isSelected ? .blue : .secondary)
                    .opacity(app.isSelected ? 1.0 : 0.5)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(app.isSelected ? .primary : .secondary)

                Text(app.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(app.isSelected ? 0.9 : 0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                app.isSelected.toggle()
            }
        }
    }
}

#Preview {
    BatchAuthViewPreviewWrapper()
}

private struct BatchAuthViewPreviewWrapper: View {
    @State private var server: XPCServer = {
        let xpcServer = XPCServer()
        xpcServer.pendingApps = [
            PendingAppItem(
                name: "Safari",
                path: "/Applications/Safari.app/Contents/MacOS/Safari",
                cdhash: "abc123hash",
                pid: 1024,
                isSelected: true
            ),
            PendingAppItem(
                name: "Xcode",
                path: "/Applications/Xcode.app/Contents/MacOS/Xcode",
                cdhash: "def456hash",
                pid: 2048,
                isSelected: true
            ),
            PendingAppItem(
                name: "Telegram",
                path: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                cdhash: "ghi789hash",
                pid: 4096,
                isSelected: false
            )
        ]
        xpcServer.remainingSeconds = 60
        return xpcServer
    }()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        BatchAuthView(
            server: server,
            onAuthenticate: {
                let count = server.pendingApps.filter(\.isSelected).count
                Logfile.appXPC.debug("[Preview] Mock Authenticate triggered for \(count, privacy: .public) apps")
            },
            onCancel: {
                Logfile.appXPC.debug("[Preview] Mock Cancel triggered")
            }
        )
        .frame(width: WindowLayout.batchAuthSize.width, height: WindowLayout.batchAuthSize.height)
        .onReceive(timer) { _ in
            if server.remainingSeconds > 0 {
                server.remainingSeconds -= 1
            }
        }
    }
}
