//
//  AboutView.swift
//  AppLocker
//
//  Created by Doe Phương on 2/5/26.
//

import SwiftUI
import AppKit

struct AboutView: View {
    let bundle = Bundle.main
    @Environment(\.openURL) private var openURL
    @State private var isCopied: Bool = false
    @State private var iconBounceTrigger: Int = 0
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 140, height: 140)
                .blur(radius: 30)
                .offset(y: -40)

            WindowDragArea {
                Color.clear
            }

            VStack(spacing: 0) {
                appIdentitySection
                    .padding(.top, 24)

                taglineSection
                    .padding(.top, 6)

                AboutArchitectureBadgesView()
                    .padding(.top, 14)

                actionsSection
                    .padding(.top, 16)

                Spacer(minLength: 8)

                footerSection
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: WindowLayout.aboutSize.width, height: WindowLayout.aboutSize.height)
    }

    // MARK: - App Identity Section

    @ViewBuilder
    private var appIdentitySection: some View {
        VStack(spacing: 8) {
            Button(action: handleIconTap) {
                Image(nsImage: bundle.appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyframeAnimator(initialValue: 1.0, trigger: iconBounceTrigger) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.08, duration: 0.14)
                SpringKeyframe(1.0, duration: 0.28, spring: .bouncy)
            }
            .help("Click to bounce")
            .accessibilityLabel("AppLocker Icon")

            VStack(spacing: 4) {
                Text(bundle.appName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                versionPill
            }
        }
    }

    @ViewBuilder
    private var versionPill: some View {
        Button(action: copyVersion) {
            HStack(spacing: 5) {
                Text("Version \(bundle.fullVersion)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                copyVersionIcon
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
            )
            .overlay(
                Capsule()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .help("Click to copy version")
        .accessibilityLabel("Version \(bundle.fullVersion)")
    }

    private var copyVersionIcon: some View {
        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isCopied ? Color.green : Color.secondary)
            .magicSymbolReplace()
    }

    // MARK: - Tagline Section

    private var taglineSection: some View {
        Text("High-Performance Process & App Security")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        HStack(spacing: 10) {
            Button {
                AppUpdater.shared.checkForUpdates()
            } label: {
                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                if let url = URL(string: "https://github.com/TranPhuong319/AppLocker") {
                    openURL(url)
                }
            } label: {
                Label("GitHub", systemImage: "link")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Footer Section

    @ViewBuilder
    private var footerSection: some View {
        VStack(spacing: 2) {
            Text("Designed & Built by TranPhuong319")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text(bundle.copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    private func handleIconTap() {
        iconBounceTrigger += 1
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    private func copyVersion() {
        NSPasteboard.general.copyText("AppLocker v\(bundle.fullVersion)")
        copyResetTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) {
            isCopied = true
        }
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}

#Preview {
    AboutView()
        .frame(
            width: WindowLayout.aboutSize.width,
            height: WindowLayout.aboutSize.height
        )
}
