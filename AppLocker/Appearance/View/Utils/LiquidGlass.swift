//
//  LiquidGlass.swift
//  AppLocker
//
//  Created by Antigravity on 16/2/26.
//

import SwiftUI

extension View {
    /// Áp dụng hiệu ứng glass tùy chỉnh cho view.
    @ViewBuilder
    func liquidGlass<S: InsettableShape, Fallback: View>(
        in shape: S,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        self.background(fallback())
    }
}
