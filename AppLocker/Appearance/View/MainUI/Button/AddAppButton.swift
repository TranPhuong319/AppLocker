//
//  AddAppButton.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
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
