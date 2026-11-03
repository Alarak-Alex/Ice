//
//  AppLanguage.swift
//  Ice
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: "IceLanguage") ?? "system") ?? .system
    }

    static func localized(_ value: String.LocalizationValue) -> String {
        let language = current
        let bundle = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        return String(localized: value, bundle: bundle, locale: language.locale)
    }

    var locale: Locale {
        Locale(identifier: self == .system ? Locale.current.identifier : rawValue)
    }
}
