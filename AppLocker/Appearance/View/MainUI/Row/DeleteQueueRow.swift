//
//  DeleteQueueRow.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct DeleteQueueRow: View {
    let app: InstalledApp
    @ObservedObject var appState: AppState

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
