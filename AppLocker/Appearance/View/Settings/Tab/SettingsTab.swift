//
//  SettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable = "Stable"
    case beta = "Beta"

    var id: String { self.rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .stable: return "Stable"
        case .beta: return "Beta"
        }
    }

    var description: LocalizedStringKey {
        switch self {
        case .stable:
            return "Get official, stable updates."
        case .beta:
            return """
                Get experimental updates.
                Note: Experimental updates are often unstable.
                """
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case security = "Security"
    case activity = "Activity"
    case appearance = "Appearance"
    case updates = "Updates"
    case diagnostics = "Diagnostics"

    var id: String { self.rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .security: return "Security"
        case .activity: return "Activity"
        case .appearance: return "Appearance"
        case .updates: return "Updates"
        case .diagnostics: return "Diagnostics"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .security: return "lock.shield"
        case .activity: return "clock.badge.checkmark"
        case .appearance: return "paintpalette"
        case .updates: return "arrow.triangle.2.circlepath"
        case .diagnostics: return "stethoscope"
        }
    }

    var preferredSize: NSSize {
        switch self {
        case .general:
            return WindowLayout.settingsGeneralSize
        case .security:
            return WindowLayout.settingsSecuritySize
        case .activity:
            return WindowLayout.settingsActivitySize
        case .appearance:
            return WindowLayout.settingsAppearanceSize
        case .updates:
            return WindowLayout.settingsUpdatesSize
        case .diagnostics:
            return WindowLayout.settingsLogsSize
        }
    }

    var minSize: NSSize {
        WindowLayout.settingsMinSize
    }
}
