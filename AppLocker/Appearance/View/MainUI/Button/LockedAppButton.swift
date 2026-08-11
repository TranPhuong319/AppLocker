//
//  LockedAppButton.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

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
