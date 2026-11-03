//
//  SettingsNavigationIdentifier.swift
//  Ice
//

import SwiftUI

/// An identifier used for navigation in the settings interface.
enum SettingsNavigationIdentifier: String, NavigationIdentifier {
    case general = "General"
    case menuBarLayout = "Menu Bar Layout"
    case menuBarAppearance = "Menu Bar Appearance"
    case hotkeys = "Hotkeys"
    case advanced = "Advanced"
    case about = "About"

    /// Bartender uses the short names "Menu Bar" and "Style" in its sidebar.
    var titleKey: String {
        switch self {
        case .menuBarLayout: "Menu Bar"
        case .menuBarAppearance: "Style"
        default: rawValue
        }
    }

    var localized: LocalizedStringKey { LocalizedStringKey(titleKey) }
}
