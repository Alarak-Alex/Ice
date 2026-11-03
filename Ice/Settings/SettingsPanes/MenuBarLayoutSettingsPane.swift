//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var isRefreshing = false
    @State private var itemCache = MenuBarItemManager.ItemCache()

    @ViewBuilder
    var body: some View {
        if #available(macOS 27.0, *) {
            ModernMenuBarLayoutSettingsPane(model: appState.modernMenuBarLayout)
        } else {
            legacyBody
        }
    }

    @ViewBuilder
    private var legacyBody: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            IceForm(alignment: .leading, spacing: 20) {
                header
                if !ScreenCapture.cachedCheckPermissions() {
                    missingScreenRecordingPermission
                }
                layoutBars
            }
            .onReceive(appState.itemManager.$itemCache) { itemCache = $0 }
            .task { refresh() }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu Bar Layout")
                    .font(.title2.weight(.semibold))
                Text("Drag items to change their order. Changes apply immediately.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                refresh()
            } label: {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRefreshing)
            .help("Refresh menu bar item images")
        }

        IceGroupBox {
            AnnotationView(
                alignment: .center,
                font: .callout.bold()
            ) {
                Label {
                    Text("Tip: you can also arrange menu bar items by Command + dragging them in the menu bar")
                } icon: {
                    Image(systemName: "lightbulb")
                }
            }
        }
    }

    @ViewBuilder
    private var layoutBars: some View {
        VStack(spacing: 25) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                layoutBar(for: section)
            }
        }
    }

    @ViewBuilder
    private var cannotArrange: some View {
        Text("Ice cannot arrange menu bar items in automatically hidden menu bars")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var missingScreenRecordingPermission: some View {
        IceGroupBox {
            Text("App icons are shown when menu bar images are unavailable.")
                .font(.callout)

            Button {
                appState.navigationState.settingsNavigationIdentifier = .advanced
            } label: {
                Text("Go to Advanced Settings")
            }
            .buttonStyle(.link)
        }
    }

    @ViewBuilder
    private func layoutBar(for section: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: section),
            section.isEnabled
        {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(sectionTitle(for: section.name))
                        .font(.headline)
                    Spacer()
                    Text(itemCache.managedItems(for: section.name).count, format: .number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 2)

                LayoutBar(section: section)
                    .overlay {
                        if itemCache.managedItems(for: section.name).isEmpty {
                            Text("Drag items here")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    private func sectionTitle(for section: MenuBarSection.Name) -> LocalizedStringKey {
        switch section {
        case .visible:
            "Visible"
        case .hidden:
            "Hidden"
        case .alwaysHidden:
            "Always Hidden"
        }
    }

    private func refresh() {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        Task {
            await appState.itemManager.cacheItemsIfNeeded(force: true)
            await appState.imageCache.updateCache()
            isRefreshing = false
        }
    }
}
