//
//  LockedAppRow.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct LockedAppRow: View {
    let app: InstalledApp
    @ObservedObject var appState: AppState
    let unfocus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(path: app.path, size: 32)

            Text(app.name)

            Spacer()

            if appState.selectedToLock.contains(app.path) {
                Image(systemName: "checkmark.circle.fill")
            }

            Button {
                withAnimation(.spring()) {
                    _ = appState.deleteQueue.insert(app.path)
                }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
            .disabled(appState.deleteQueue.contains(app.path))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { unfocus() }
        .opacity(appState.deleteQueue.contains(app.path) ? 0.3 : 1.0)
    }
}
