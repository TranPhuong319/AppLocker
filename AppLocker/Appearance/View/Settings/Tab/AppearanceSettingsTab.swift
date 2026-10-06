//
//  AppearanceSettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

struct AppearanceSettingsTab: View {
    let isMock: Bool

    @AppStorage("appTheme") private var appTheme: String = "System"

    init(isMock: Bool = false) {
        self.isMock = isMock
    }

    var body: some View {
        Form {
            Section(header: Text("Appearance")) {
                HStack(alignment: .top) {
                    Text("Appearance mode")
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    HStack(spacing: 16) {
                        ForEach(ThemeMode.allCases) { mode in
                            Button(action: { selectTheme(mode.rawValue) }, label: {
                                ThemeThumbnailView(mode: mode, isSelected: appTheme == mode.rawValue)
                            })
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .formStyle(.grouped)
    }

    private func selectTheme(_ theme: String) {
        appTheme = theme
        if !isMock, let appDelegate = NSApp.appDelegate {
            appDelegate.applyTheme(theme)
        }
    }
}

#Preview {
    AppearanceSettingsTab(isMock: true)
}
