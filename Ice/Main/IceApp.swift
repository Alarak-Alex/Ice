//
//  IceApp.swift
//  Ice
//

import SwiftUI

@main
struct IceApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate
    @ObservedObject var appState = AppState()
    @AppStorage("IceLanguage") private var language = AppLanguage.system.rawValue

    private var locale: Locale {
        AppLanguage(rawValue: language)?.locale ?? Locale.current
    }

    init() {
        NSSplitViewItem.swizzle()
        MigrationManager.migrateAll(appState: appState)
        appDelegate.assignAppState(appState)
    }

    var body: some Scene {
        SettingsWindow(appState: appState)
            .environment(\.locale, locale)
        PermissionsWindow(appState: appState)
            .environment(\.locale, locale)
    }
}
