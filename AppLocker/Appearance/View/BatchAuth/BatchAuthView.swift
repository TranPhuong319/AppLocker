//
//  BatchAuthView.swift
//  AppLocker
//
//  Created by Doe Phương on 31/7/26.
//

import SwiftUI
import AppKit

struct BatchAuthView: View {
    @Bindable var coordinator: AuthCoordinator
    var onAuthenticate: () -> Void
    var onCancel: () -> Void
    @State private var maxButtonWidth: CGFloat?

    var selectedCount: Int {
        coordinator.pendingApps.filter { $0.isSelected }.count
    }

    var headerTitle: String {
        let count = coordinator.pendingApps.count
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
                        ForEach($coordinator.pendingApps) { $app in
                            BatchAppRowView(app: $app)
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
                    coordinator.remainingSeconds
                )
            )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(coordinator.remainingSeconds)))
                .animation(.snappy(duration: 0.3), value: coordinator.remainingSeconds)
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
                        .equalWidthButtonLabel(minWidth: maxButtonWidth)
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
                    .equalWidthButtonLabel(minWidth: maxButtonWidth)
                }
            )
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedCount == 0)
            .animation(.snappy(duration: 0.25), value: selectedCount)
            .keyboardShortcut(.defaultAction)
        }
        .syncEqualWidth(into: $maxButtonWidth)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}

struct BatchAppRowView: View {
    @Binding var app: PendingAppItem

    var body: some View {
        HStack(spacing: 12) {
            checkmarkIndicator

            AppIconView(path: app.path, size: 32)
                .opacity(app.isSelected ? 1.0 : 0.5)

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
            withAnimation(.snappy(duration: 0.25)) {
                app.isSelected.toggle()
            }
        }
    }

    private var checkmarkIndicator: some View {
        Image(systemName: app.isSelected ? "checkmark.circle.fill" : "circle")
            .magicSymbolReplace()
            .font(.title3)
            .foregroundStyle(app.isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
            .accessibilityLabel(app.isSelected ? "Selected" : "Unselected")
    }
}

#Preview {
    BatchAuthViewPreviewWrapper()
}

private struct BatchAuthViewPreviewWrapper: View {
    @State private var coordinator: AuthCoordinator = {
        let authCoord = AuthCoordinator()
        authCoord.pendingApps = [
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
        authCoord.remainingSeconds = 60
        return authCoord
    }()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        BatchAuthView(
            coordinator: coordinator,
            onAuthenticate: {
                let count = coordinator.pendingApps.filter(\.isSelected).count
                Logfile.appXPC.debug("[Preview] Mock Authenticate triggered for \(count, privacy: .public) apps")
            },
            onCancel: {
                Logfile.appXPC.debug("[Preview] Mock Cancel triggered")
            }
        )
        .frame(width: WindowLayout.batchAuthSize.width, height: WindowLayout.batchAuthSize.height)
        .onReceive(timer) { _ in
            if coordinator.remainingSeconds > 0 {
                coordinator.remainingSeconds -= 1
            }
        }
    }
}
