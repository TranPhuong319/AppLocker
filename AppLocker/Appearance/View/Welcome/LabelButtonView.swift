//
//  LabelButtonView.swift
//  AppLocker
//
//  Created by Doe Phương on 21/2/26.
//

import SwiftUI

struct LabelButtonView: View {
    let label: LocalizedStringKey
    let symbol: String
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 24))
                Text(label)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .brightness(isHovering && !isDisabled ? 0.1 : 0)  // Tăng độ sáng 10% khi hover
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(isDisabled ? 0.2 : 0.5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isDisabled ? 0 : 0.1), radius: 2, x: 0, y: 1)
            .opacity(isDisabled ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            if !isDisabled {
                isHovering = hovering
            }
        }
    }
}
