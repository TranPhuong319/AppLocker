//
//  AboutArchitectureBadgesView.swift
//  AppLocker
//
//  Created by AppLocker
//

import SwiftUI

struct AboutArchitectureBadgesView: View {
    @State private var isExtensionActive: Bool
    @State private var showSystemInfo: Bool = false

    init(isExtensionActive: Bool? = nil) {
        _isExtensionActive = State(initialValue: isExtensionActive ?? !AppState.shared.manager.isProtectionDisabled)
    }

    var body: some View {
        HStack(spacing: 8) {
            badgePill(
                icon: isExtensionActive ? "checkmark.shield.fill" : "shield.slash.fill",
                text: isExtensionActive ? "Endpoint Security" : "Extension Inactive",
                color: isExtensionActive ? .green : .orange
            )

            badgePill(
                icon: "swift",
                text: "Swift Native",
                color: .orange
            )

            architectureButton
        }
        .onReceive(NotificationCenter.default.publisher(for: .protectionStatusDidChange)) { _ in
            isExtensionActive = !AppState.shared.manager.isProtectionDisabled
        }
    }

    @ViewBuilder
    private var architectureButton: some View {
        Button {
            showSystemInfo.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .semibold))
                Text(architectureName)
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.secondary.opacity(0.12))
            )
            .overlay(
                Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSystemInfo, arrowEdge: .trailing) {
            SystemInfoPopoverView()
        }
        .help("Click to view system & architecture details")
    }

    private var architectureName: LocalizedStringKey {
        #if arch(arm64)
        return "Apple Silicon"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Universal"
        #endif
    }

    private func badgePill(icon: String, text: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.25), lineWidth: 0.5)
        )
    }
}
