//
//  MainUIButtons.swift
//  AppLocker
//
//  Created by Doe Phương on 15/8/26.
//

import SwiftUI

struct AddAppRow: View {
    let app: InstalledApp
    let isSelected: Bool
    let onToggle: () -> Void
    let onUnfocus: () -> Void

    init(
        for app: InstalledApp,
        isSelected: Bool,
        onToggle: @escaping () -> Void,
        onUnfocus: @escaping () -> Void
    ) {
        self.app = app
        self.isSelected = isSelected
        self.onToggle = onToggle
        self.onUnfocus = onUnfocus
    }

    var body: some View {
        Button {
            onUnfocus()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                onToggle()
            }
        } label: {
            HStack(spacing: 12) {
                AppIconView(path: app.path, size: 32)

                Text(app.name)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .font(.title3)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppRowButtonStyle())
    }
}

struct DeleteQueueRow: View {
    let app: InstalledApp
    var appState: AppState

    init(for app: InstalledApp, appState: AppState) {
        self.app = app
        self.appState = appState
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(path: app.path, size: 32)
            Text(app.name)
            Spacer()
            Button {
                withAnimation {
                    appState.deleteQueue.remove(app.path)
                    if appState.deleteQueue.isEmpty { appState.showingDeleteQueue = false }
                }
            } label: {
                Image(systemName: "minus.circle").foregroundStyle(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .focusable(false)
    }
}

struct LockedAppRow: View {
    let app: InstalledApp
    let isDeleting: Bool
    var isMissing: Bool = false
    let onDelete: () -> Void
    let onUnfocus: () -> Void

    init(
        for app: InstalledApp,
        isDeleting: Bool,
        isMissing: Bool = false,
        onDelete: @escaping () -> Void,
        onUnfocus: @escaping () -> Void
    ) {
        self.app = app
        self.isDeleting = isDeleting
        self.isMissing = isMissing
        self.onDelete = onDelete
        self.onUnfocus = onUnfocus
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(path: app.path, size: 32, isMissing: isMissing)
                .opacity(isMissing ? 0.5 : 1.0)
                .grayscale(isMissing ? 0.6 : 0.0)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .foregroundStyle(isMissing ? .secondary : .primary)

                if isMissing {
                    Text(String(localized: "Missing"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: isMissing)

            Spacer()

            Button {
                withAnimation(.spring()) {
                    onDelete()
                }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
            .disabled(isDeleting)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onUnfocus() }
        .opacity(isDeleting ? 0.3 : (isMissing ? 0.6 : 1.0))
    }
}

struct MissingAppRow: View {
    let app: InstalledApp

    init(for app: InstalledApp) {
        self.app = app
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(path: app.path, size: 32, isMissing: true)
                .opacity(0.5)
                .grayscale(0.6)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text(app.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .opacity(0.7)
    }
}
