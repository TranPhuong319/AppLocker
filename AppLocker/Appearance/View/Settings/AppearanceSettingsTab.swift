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
        if !isMock, let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.applyTheme(theme)
        }
    }
}

private struct ThemeThumbnailView: View {
    let mode: ThemeMode
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                // 1. Wallpaper background
                wallpaperLayer

                // 2. Top menu bar with Apple logo
                menuBarLayer

                // 3. Top floating search bar / pill
                topPillLayer

                // 4. Bottom window with traffic lights
                bottomWindowLayer
            }
            .frame(width: 68, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color(nsColor: .controlAccentColor) : Color.clear, lineWidth: 2.5)
                    .padding(-3)
            )
            .shadow(color: .black.opacity(isSelected ? 0.25 : 0.1), radius: 2, y: 1)

            Text(mode.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var wallpaperLayer: some View {
        switch mode {
        case .light:
            lightWallpaper
        case .dark:
            darkWallpaper
        case .system:
            HStack(spacing: 0) {
                lightWallpaper
                darkWallpaper
            }
        }
    }

    @ViewBuilder
    private var menuBarLayer: some View {
        switch mode {
        case .light:
            miniMenuBar(isDark: false, showLogo: true)
        case .dark:
            miniMenuBar(isDark: true, showLogo: true)
        case .system:
            HStack(spacing: 0) {
                miniMenuBar(isDark: false, showLogo: true)
                    .frame(width: 34)
                miniMenuBar(isDark: true, showLogo: false)
                    .frame(width: 34)
            }
        }
    }

    @ViewBuilder
    private var topPillLayer: some View {
        switch mode {
        case .light:
            miniPill(isDark: false)
                .padding(.top, 9)
        case .dark:
            miniPill(isDark: true)
                .padding(.top, 9)
        case .system:
            HStack(spacing: 0) {
                miniPillHalf(isDark: false)
                miniPillHalf(isDark: true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            .padding(.top, 9)
        }
    }

    @ViewBuilder
    private var bottomWindowLayer: some View {
        VStack {
            Spacer()
            switch mode {
            case .light:
                miniWindow(isDark: false)
            case .dark:
                miniWindow(isDark: true)
            case .system:
                HStack(spacing: 0) {
                    miniWindowSplit(isDark: false)
                    miniWindowSplit(isDark: true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
        }
    }

    private var lightWallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.70, blue: 0.98),
                    Color(red: 0.16, green: 0.44, blue: 0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Path { path in
                path.move(to: CGPoint(x: 35, y: 0))
                path.addCurve(
                    to: CGPoint(x: 68, y: 28),
                    control1: CGPoint(x: 45, y: 12),
                    control2: CGPoint(x: 56, y: 18)
                )
                path.addLine(to: CGPoint(x: 68, y: 0))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.35), Color.blue.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var darkWallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.18, blue: 0.48),
                    Color(red: 0.04, green: 0.08, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Path { path in
                path.move(to: CGPoint(x: 35, y: 0))
                path.addCurve(
                    to: CGPoint(x: 68, y: 28),
                    control1: CGPoint(x: 45, y: 12),
                    control2: CGPoint(x: 56, y: 18)
                )
                path.addLine(to: CGPoint(x: 68, y: 0))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.35), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private func miniMenuBar(isDark: Bool, showLogo: Bool) -> some View {
        HStack {
            if showLogo {
                Image(systemName: "apple.logo")
                    .font(.system(size: 4))
                    .foregroundStyle(isDark ? .white.opacity(0.8) : .black.opacity(0.6))
                    .padding(.leading, 3)
            }
            Spacer()
        }
        .frame(height: 6)
        .background(isDark ? Color.black.opacity(0.4) : Color.white.opacity(0.5))
    }

    private func miniPill(isDark: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(isDark ? Color(red: 0.10, green: 0.20, blue: 0.60) : Color(red: 0.62, green: 0.78, blue: 0.98))
            .frame(width: 52, height: 9)
            .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
    }

    private func miniPillHalf(isDark: Bool) -> some View {
        Rectangle()
            .fill(isDark ? Color(red: 0.10, green: 0.20, blue: 0.60) : Color(red: 0.62, green: 0.78, blue: 0.98))
            .frame(width: 26, height: 9)
    }

    private func miniWindow(isDark: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isDark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)

            HStack(spacing: 3) {
                Circle().fill(Color(red: 1.0, green: 0.38, blue: 0.35)).frame(width: 4, height: 4)
                Circle().fill(Color(red: 1.0, green: 0.75, blue: 0.18)).frame(width: 4, height: 4)
                Circle().fill(Color(red: 0.16, green: 0.80, blue: 0.26)).frame(width: 4, height: 4)
            }
            .padding(.leading, 7)
            .padding(.top, 4.5)
        }
        .frame(width: 54, height: 22)
    }

    private func miniWindowSplit(isDark: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(isDark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white)

            HStack(spacing: 3) {
                Circle().fill(Color(red: 1.0, green: 0.38, blue: 0.35)).frame(width: 4, height: 4)
                Circle().fill(Color(red: 1.0, green: 0.75, blue: 0.18)).frame(width: 4, height: 4)
            }
            .padding(.leading, 7)
            .padding(.top, 4.5)
        }
        .frame(width: 27, height: 22)
    }
}

#Preview {
    AppearanceSettingsTab(isMock: true)
}
