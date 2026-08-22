//
//  MainUIButtons.swift
//  AppLocker
//
//  Created by Doe Phương on 15/8/26.
//

import SwiftUI

struct AddAppButton: View {
    let app: InstalledApp
    let isSelected: Bool
    let onToggle: () -> Void
    let unfocus: () -> Void

    var body: some View {
        Button {
            unfocus()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                onToggle()
            }
        } label: {
            HStack(spacing: 12) {
                AppIconView(path: app.path, size: 32)

                Text(app.name)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
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

struct DeleteAppButton: View {
    let app: InstalledApp
    var appState: AppState

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
                Image(systemName: "minus.circle").foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .focusable(false)
    }
}

struct LockedAppButton: View {
    let app: InstalledApp
    let isDeleting: Bool
    let onDelete: () -> Void
    let unfocus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(path: app.path, size: 32)

            Text(app.name)

            Spacer()

            Button {
                withAnimation(.spring()) {
                    onDelete()
                }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
            .disabled(isDeleting)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { unfocus() }
        .opacity(isDeleting ? 0.3 : 1.0)
    }
}
