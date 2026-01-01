//
//  AppRow.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct AppRow: View {
    let app: InstalledApp
    @ObservedObject var appState: AppState
    let unfocus: () -> Void

    var body: some View {
        Button {
            unfocus()
            guard !appState.pendingLocks.contains(app.path) else { return }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                if appState.selectedToLock.contains(app.path) {
                    appState.selectedToLock.remove(app.path)
                } else {
                    appState.selectedToLock.insert(app.path)
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 32, height: 32)
                }

                Text(app.name)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                if appState.pendingLocks.contains(app.path) {
                    Text("Locking...")
                        .italic()
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else if appState.selectedToLock.contains(app.path) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .opacity(appState.selectedToLock.contains(app.path) ? 0.5 : 1.0)
        }
        .buttonStyle(AppRowButtonStyle())
    }
}
