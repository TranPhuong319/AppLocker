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
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 32, height: 32).cornerRadius(6)
            }
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
    }
}
