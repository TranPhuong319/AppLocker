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
        LocalizedStringKey(rawValue)
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
    case updates = "Updates"
    case appearance = "Appearance"

    var id: String { self.rawValue }

    var displayName: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .security: return "lock.shield"
        case .updates: return "arrow.triangle.2.circlepath"
        case .appearance: return "paintpalette"
        }
    }
}
