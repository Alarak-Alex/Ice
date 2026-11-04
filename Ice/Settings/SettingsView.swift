//
//  SettingsView.swift
//  Ice
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var navigationState: AppNavigationState
    @AppStorage("IceLanguage") private var language = AppLanguage.system.rawValue

    private var locale: Locale {
        AppLanguage(rawValue: language)?.locale ?? Locale.current
    }

    var body: some View {
        // Closed windows must not keep SwiftUI scroll prefetching alive.
        if navigationState.isSettingsPresented {
            settingsContent
        }
    }

    private var settingsContent: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(navigationState.settingsNavigationIdentifier.localized)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: navigationState.goBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .labelStyle(.iconOnly)
                .disabled(!navigationState.canGoBack)
                .keyboardShortcut("[", modifiers: .command)
                .help("Back")

                Button(action: navigationState.goForward) {
                    Label("Forward", systemImage: "chevron.right")
                }
                .labelStyle(.iconOnly)
                .disabled(!navigationState.canGoForward)
                .keyboardShortcut("]", modifiers: .command)
                .help("Forward")
            }

            if navigationState.settingsNavigationIdentifier == .menuBarLayout {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        NotificationCenter.default.post(name: Notification.Name("IceMenuBarSearchRequested"), object: nil)
                    } label: {
                        Label("Search Menu Bar Items", systemImage: "magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut("f", modifiers: .command)
                    .help("Search Menu Bar Items")

                    Button {
                        NotificationCenter.default.post(name: Notification.Name("IceMenuBarRefreshRequested"), object: nil)
                    } label: {
                        Label("Refresh Menu Bar Items", systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Refresh Menu Bar Items")
                }
            }
        }
        .environment(\.locale, locale)
        .id(language)
    }

    @ViewBuilder
    private var sidebar: some View {
        SettingsSidebar(selection: navigationState.settingsNavigationIdentifier, language: language) { identifier in
            navigationState.settingsNavigationIdentifier = identifier
        }
        .removeSidebarToggle()
        .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
    }

    @ViewBuilder
    private var detailView: some View {
        switch navigationState.settingsNavigationIdentifier {
        case .general:
            GeneralSettingsPane()
        case .menuBarLayout:
            MenuBarLayoutSettingsPane()
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane()
        case .hotkeys:
            HotkeysSettingsPane()
        case .advanced:
            AdvancedSettingsPane()
        case .about:
            AboutSettingsPane()
        }
    }

}
