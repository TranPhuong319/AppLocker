//
//  SectionHeader.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.secondary.opacity(0.8))
                .layoutPriority(1)

            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
        .padding(.top, 6)
    }
}
