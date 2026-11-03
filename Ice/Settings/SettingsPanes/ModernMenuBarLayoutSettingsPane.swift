import SwiftUI

struct ModernMenuBarLayoutSettingsPane: View {
    @ObservedObject var model: ModernMenuBarLayoutModel
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var isNamingProfile = false
    @State private var profileName = ""
    @State private var renamingProfileID: UUID?
    @State private var isMissingPresented = false
    @AppStorage("IceMenuBarLayoutSpacing") private var layoutSpacing = "default"
    @AppStorage("IceMenuBarLayoutShowAppIcons") private var showAppIcons = false
    @AppStorage("IceMenuBarLayoutImageLocations") private var imageLocations = "shown"

    var body: some View {
        IceForm(
            alignment: .leading,
            padding: EdgeInsets(top: 16, leading: 32, bottom: 32, trailing: 32),
            spacing: 12
        ) {
            SettingsPaneHeader(
                title: "Menu Bar",
                subtitle: "Drag items between sections to rearrange the menu bar.",
                systemImage: "rectangle.bottomthird.inset.filled"
            )
            .controlSize(.large)
            .frame(minHeight: 181)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))

            configurationSection
                .padding(.bottom, 12)

            ForEach(MenuBarLayoutSection.allCases) { section in
                sectionBar(section)
            }

            paletteSection
            customizationSection

            if let notice = model.notice {
                HStack {
                    Text(notice).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo") { Task { await model.undo() } }
                        .disabled(!model.canUndo || model.isBusy)
                }
            }
        }
        .popover(isPresented: $isSearchPresented, attachmentAnchor: .point(.top), arrowEdge: .top) {
            TextField("Search Menu Bar Items", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(12)
                .frame(width: 260)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("IceMenuBarSearchRequested"))) { _ in
            isSearchPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("IceMenuBarRefreshRequested"))) { _ in
            Task { await model.refresh() }
        }
        .task { await model.refresh() }
        .alert("Configuration Name", isPresented: $isNamingProfile) {
            TextField("Name", text: $profileName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let id = renamingProfileID { model.renameProfile(id, to: profileName) }
                else { model.createProfile(named: profileName) }
            }
        }
        .alert("Unable to arrange menu bar items", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var configurationSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.bottomthird.inset.filled")
                Text("Configuration").font(.headline)
                Spacer()
                Menu {
                    Button("Rename Configuration…") { nameProfile(model.activeProfileID) }
                    Button("New Configuration…") { nameProfile(nil) }
                    Button("Delete Configuration", role: .destructive) { Task { await model.deleteActiveProfile() } }
                        .disabled(model.profiles.count < 2)
                } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Manage Configurations")
            }
            .padding(.horizontal, 1)

            VStack(spacing: 0) {
                ForEach(model.profiles) { profile in
                    HStack(spacing: 0) {
                        Button { Task { await model.selectProfile(profile.id) } } label: {
                            HStack {
                                Text(profile.name).fontWeight(model.activeProfileID == profile.id ? .semibold : .regular)
                                if model.activeProfileID == profile.id {
                                    Text("Active")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(.white.opacity(0.18), in: Capsule())
                                }
                                Spacer()
                            }
                            .padding(.leading, 12)
                            .frame(height: 42)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if model.activeProfileID == profile.id {
                            Menu {
                                Button("Rename Configuration…") { nameProfile(profile.id) }
                                Button("Delete Configuration", role: .destructive) { Task { await model.deleteActiveProfile() } }
                                    .disabled(model.profiles.count < 2)
                            } label: { Image(systemName: "ellipsis").frame(width: 32) }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .accessibilityLabel("Edit Configuration")
                        }
                    }
                    .foregroundStyle(model.activeProfileID == profile.id ? Color.white : Color.primary)
                    .background(model.activeProfileID == profile.id ? Color.accentColor : Color.clear)
                }
                HStack(spacing: 14) {
                    Button { nameProfile(nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New Configuration…")
                    Button { Task { await model.deleteActiveProfile() } } label: { Image(systemName: "minus") }
                        .disabled(model.profiles.count < 2)
                        .accessibilityLabel("Delete Configuration")
                    Spacer()
                    Text(profileCountLabel).font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(12)

                Divider()

                HStack(spacing: 10) {
                    Toggle("Automatically use this configuration for current display", isOn: Binding(
                        get: { model.activeProfile?.automaticDisplayID == NSScreen.main?.displayID },
                        set: { model.setAutomaticForCurrentDisplay($0) }
                    ))
                    .toggleStyle(.checkbox)
                    Spacer()
                    Text(model.currentDisplayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(height: 42)
                .padding(.horizontal, 12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
            .disabled(model.isBusy)
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func nameProfile(_ id: UUID?) {
        renamingProfileID = id
        profileName = id.flatMap { id in model.profiles.first { $0.id == id }?.name } ?? ""
        isNamingProfile = true
    }

    @ViewBuilder
    private func sectionBar(_ section: MenuBarLayoutSection) -> some View {
        let sectionEntries = filtered(model.displayEntries(in: section))
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: section.symbol)
                Text(section.title).font(.headline)
                Spacer()
                if section == .visible && !model.canEdit && !model.isRefreshing {
                    Button("Allow Menu Bar Arrangement…") { model.authorize() }
                        .buttonStyle(.link)
                } else if section == .visible {
                    Button("Missing Items") { isMissingPresented.toggle() }
                        .buttonStyle(.link)
                        .popover(isPresented: $isMissingPresented, arrowEdge: .top) {
                            missingItemsPopover
                        }
                } else if !model.canChangeVisibility {
                    Button("Allow Menu Bar Visibility…") { model.authorizeVisibility() }
                        .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 2)

            ModernMenuBarCollection(
                entries: sectionEntries,
                images: imageLocations == "never" || (imageLocations == "shown" && section != .visible)
                    ? [:] : model.itemImages,
                showAppIcons: showAppIcons,
                isEditable: model.canEdit && !model.isBusy,
                emptyPlaceholder: sectionEntries.isEmpty && section != .visible && !model.isRefreshing
                    ? AppLanguage.localized("Drag items here") : nil,
                onDrop: { source, index in
                    let targetID = sectionEntries.dropFirst(max(0, index)).first { $0.id != source }?.id
                    Task { await model.drop(source, in: section, before: targetID) }
                },
                onSpacerChanged: model.updateSpacer,
                onRemoveSpacer: model.removeSpacer
            )
            .frame(height: 76)
            .background(Color(red: 136 / 255, green: 140 / 255, blue: 143 / 255))
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 10)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.25), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .padding(.vertical, 2)
    }

    private func filtered(_ entries: [ModernMenuBarLayoutModel.Entry]) -> [ModernMenuBarLayoutModel.Entry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var missingItemsPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Missing Items").font(.headline)
            let missing = model.entries.filter { $0.positionKey == nil }
            if missing.isEmpty {
                Text("No missing items.").foregroundStyle(.secondary)
            } else {
                ForEach(missing) { entry in
                    Label(entry.name, systemImage: "questionmark.circle")
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(width: 250)
    }

    private var profileCountLabel: String {
        if AppLanguage.current == .simplifiedChinese { return "\(model.profiles.count) 个配置" }
        return model.profiles.count == 1 ? "1 profile" : "\(model.profiles.count) profiles"
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette")
                Text("Palette").font(.headline)
            }

            HStack(spacing: 10) {
                MenuBarSpacerPaletteView()
                    .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 36)
            .frame(height: 50)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

            Text("Drag the label to the Shown or Hidden section to add spacing. Click a spacer to edit it; right-click to remove it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var customizationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                Text("Customization").font(.headline)
            }

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu bar item spacing").fontWeight(.semibold)
                        Text("Change the spacing in macOS. Log out and back in for all items to use the new spacing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Menu bar item spacing", selection: Binding(
                        get: { MenuBarLayoutSpacing(rawValue: layoutSpacing) ?? .standard },
                        set: { spacing in
                            do {
                                try MenuBarLayoutSpacingPreferences.save(spacing)
                                layoutSpacing = spacing.rawValue
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        }
                    )) {
                        ForEach(MenuBarLayoutSpacing.allCases, id: \.rawValue) { spacing in
                            Text(LocalizedStringKey(spacing.title)).tag(spacing)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
                .frame(minHeight: 55)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show App icons").fontWeight(.semibold)
                        Text("Show App icons beside bar items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Show App icons", isOn: $showAppIcons)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .frame(minHeight: 55)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Display bar item images").fontWeight(.semibold)
                        Text("Choose where to show menu bar item images. Other sections show App icons.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Display bar item images", selection: $imageLocations) {
                        Text("Only in Shown Items").tag("shown")
                        Text("Shown and Hidden Items").tag("shownAndHidden")
                        Text("Never").tag("never")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
                .frame(minHeight: 55)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recapture Items").fontWeight(.semibold)
                        Text("Refresh the images for all hidden items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Recapture") {
                        Task { await model.recaptureImages() }
                    }
                    .controlSize(.small)
                    .disabled(model.isBusy)
                }
                .frame(minHeight: 55)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Groups").fontWeight(.semibold)
                        Text("Groups will return in a future update.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(minHeight: 55)
            }
            .padding(.horizontal, 12)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.vertical, 2)
    }
}
