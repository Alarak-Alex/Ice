import Foundation

enum MenuBarLayoutSpacing: String, CaseIterable {
    case standard = "default"
    case small = "compact"
    case tiny
    case none

    var title: String {
        switch self {
        case .standard: "Default spacing"
        case .small: "Small Spacing"
        case .tiny: "Tiny Spacing"
        case .none: "No Spacing"
        }
    }

    var value: Int? {
        switch self {
        case .standard: nil
        case .small: 8
        case .tiny: 2
        case .none: 0
        }
    }
}

enum MenuBarLayoutSpacingPreferences {
    private static let keys = ["NSStatusItemSpacing", "NSStatusItemSelectionPadding"]

    private enum Failure: LocalizedError {
        case save, rollback
        var errorDescription: String? {
            AppLanguage.localized(self == .save
                ? "Could not save menu bar spacing. Your previous settings were restored."
                : "Could not save menu bar spacing or restore your previous settings. Please try again.")
        }
    }

    /// Host-specific overrides must be cleared or they mask the global spacing.
    static func save(_ spacing: MenuBarLayoutSpacing, applicationID: CFString = kCFPreferencesAnyApplication) throws {
        let hosts = [kCFPreferencesAnyHost, kCFPreferencesCurrentHost]
        func read(_ host: CFString) -> [String: Any] {
            keys.reduce(into: [:]) { values, key in
                values[key] = CFPreferencesCopyValue(key as CFString, applicationID, kCFPreferencesCurrentUser, host)
            }
        }
        func write(_ values: [String: Any], _ host: CFString) -> Bool {
            CFPreferencesSetMultiple(values as CFDictionary, keys.filter { values[$0] == nil } as CFArray,
                                     applicationID, kCFPreferencesCurrentUser, host)
            return CFPreferencesSynchronize(applicationID, kCFPreferencesCurrentUser, host)
        }
        let original = hosts.map(read)
        let values = spacing.value.map { value in Dictionary(uniqueKeysWithValues: keys.map { ($0, value as Any) }) } ?? [:]
        let desired = [values, [:]]
        var saved = true
        for (index, host) in hosts.enumerated() {
            if !write(desired[index], host) { saved = false }
        }
        guard saved && hosts.enumerated().allSatisfy({ (read($0.element) as NSDictionary).isEqual(to: desired[$0.offset]) }) else {
            var restored = true
            for (index, host) in hosts.enumerated() {
                if !write(original[index], host) { restored = false }
            }
            let matches = hosts.enumerated().allSatisfy { (read($0.element) as NSDictionary).isEqual(to: original[$0.offset]) }
            throw restored && matches ? Failure.save : Failure.rollback
        }
    }
}
