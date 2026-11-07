//
//  DiagnosticsSettingsTab+AutoScroll.swift
//  AppLocker
//
//  Created by Doe Phương on 03/10/26.
//

import SwiftUI

// MARK: - Search Focus

/// Binds the `.searchable` field focus on macOS 15+; no-op on earlier systems.
struct LogSearchFocusModifier: ViewModifier {
    let isFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.searchFocused(isFocused)
        } else {
            content
        }
    }
}
