//
//  AppRowButtonStyle.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct AppRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                // EN: Rounded background when pressed.
                // VI: Nền bo góc khi nhấn.
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.15) : Color.clear)
                    .padding(.horizontal, 4) // EN: Keep some gap from edges. VI: Tạo khoảng cách với mép.
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Rectangle()) // EN: Preserve full-row hit testing. VI: Giữ khả năng bấm toàn dòng.
    }
}
