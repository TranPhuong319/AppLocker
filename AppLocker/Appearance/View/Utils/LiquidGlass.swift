//
//  LiquidGlass.swift
//  AppLocker
//
//  Created by Antigravity on 16/2/26.
//

import SwiftUI

extension View {
    /// Áp dụng hiệu ứng Liquid Glass (kính lỏng) cao cấp.
    /// Trên macOS 16 (Tahoe) trở lên sẽ sử dụng API chính chủ, các bản cũ hơn sẽ dùng bản fallback tùy chỉnh.
    @ViewBuilder
    func liquidGlass<S: InsettableShape, Fallback: View>(
        in shape: S,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        if #available(macOS 26.0, *) {
            // Hiệu ứng Liquid Glass chính thức trên macOS Tahoe
            // API: self.glassEffect(.clear, in: shape)
            self.glassEffect(.clear, in: shape)
        } else {
            // Fallback được định nghĩa riêng bởi từng View gọi
            fallback()
        }
    }
}
