import ApplicationServices
import Cocoa
import UniformTypeIdentifiers

/// MenuBarAgent no longer publishes an individual WindowServer window per item.
@MainActor
final class ModernMenuBarLayoutModel: ObservableObject {
    typealias Entry = ModernMenuBarEntry

    @Published private(set) var entries = [Entry]()
    @Published private(set) var isRefreshing = false
    @Published private(set) var canEdit = false
    @Published private(set) var canUndo = false
    @Published private(set) var isApplying = false
    @Published private(set) var isCapturingImages = false
    @Published private(set) var canChangeVisibility = false
    @Published private(set) var profiles = [MenuBarLayoutProfile]()
    @Published private(set) var activeProfileID: UUID?
    @Published private(set) var itemImages = [String: NSImage]()
    @Published private(set) var areHiddenItemsRevealed = false
    @Published var selectedEntry: Entry?
    @Published var errorMessage: String?
    @Published private(set) var notice: String?

    private let queue = DispatchQueue(label: "com.jordanbaird.Ice.menuBarLayout", qos: .userInitiated)
    private weak var appState: AppState?
    private var authorizedURL: URL?
    private var visibilityAuthorizedURL: URL?
    private var visibility = [String: Bool]()
    private var nativePositions = [String: Double]()
    private var previousPositions: [String: Double]?
    private var writtenPositions: [String: Double]?
    private var previousSections: [String: MenuBarLayoutSection]?
    private var previousVisibility = [String: Bool]()
    private var writtenVisibility = [String: Bool]()
    private var previousProfiles: [MenuBarLayoutProfile]?
    private var previousActiveProfileID: UUID?
    private var orderVerificationTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let positionStoreOverride: MenuBarPositionStore?
    private let visibilityStoreOverride: MenuBarVisibilityStore?
    private let spacerManager: (any MenuBarSpacerManaging)?
    private let discover: ([ModernMenuBarDiscovery.Application], [String: Double], [CGRect], String) -> [Entry]
    private var lastDisplayID: UInt32?
    private var isScanning = false
    private var refreshPending = false
    private lazy var imageStore = ModernMenuBarImageStore()

    var isBusy: Bool { isRefreshing || isApplying || isCapturingImages }

    var activeProfile: MenuBarLayoutProfile? { profiles.first { $0.id == activeProfileID } }

    var currentDisplayName: String { NSScreen.main?.localizedName ?? AppLanguage.localized("Current Display") }

    private var currentDisplayID: UInt32? { NSScreen.main?.displayID }

    private var visibilityStore: MenuBarVisibilityStore {
        if let visibilityStoreOverride { return visibilityStoreOverride }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return MenuBarVisibilityStore(
            url: visibilityAuthorizedURL ?? home.appendingPathComponent("Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist"),
            backupURL: home.appendingPathComponent("Library/Application Support/Ice/MenuBarVisibility.before.plist")
        )
    }

    private var revealVisibilityStore: MenuBarVisibilityStore {
        var store = visibilityStore
        store.temporaryVisibilityJournalName = "MenuBarReveal.visibility.plist"
        return store
    }

    private var menuBands: [CGRect] {
        NSScreen.screens.map {
            let bounds = CGDisplayBounds($0.displayID)
            return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 64)
        }
    }

    private var store: MenuBarPositionStore {
        if let positionStoreOverride { return positionStoreOverride }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return MenuBarPositionStore(
            url: authorizedURL ?? home.appendingPathComponent("Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist"),
            backupURL: home.appendingPathComponent("Library/Application Support/Ice/MenuBarLayout.before.plist")
        )
    }

    init(appState: AppState? = nil, defaults: UserDefaults = .standard, positionStore: MenuBarPositionStore? = nil,
         visibilityStore: MenuBarVisibilityStore? = nil, spacerManager: (any MenuBarSpacerManaging)? = nil,
         discover: @escaping ([ModernMenuBarDiscovery.Application], [String: Double], [CGRect], String) -> [Entry] = ModernMenuBarDiscovery.scan) {
        self.appState = appState
        self.defaults = defaults
        self.discover = discover
        self.spacerManager = spacerManager
        positionStoreOverride = positionStore
        visibilityStoreOverride = visibilityStore
        if let data = defaults.data(forKey: "MenuBarLayoutProfiles.v1"),
           let saved = try? JSONDecoder().decode([MenuBarLayoutProfile].self, from: data), !saved.isEmpty {
            profiles = saved
        } else { profiles = [MenuBarLayoutProfile(name: "Default")] }
        activeProfileID = defaults.string(forKey: "MenuBarLayoutActiveProfile.v1").flatMap(UUID.init(uuidString:))
        if !profiles.contains(where: { $0.id == activeProfileID }) { activeProfileID = profiles.first?.id }
        if let data = defaults.data(forKey: "MenuBarLayoutBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale), !stale {
                _ = url.startAccessingSecurityScopedResource()
                authorizedURL = url
            }
        }
        if let data = defaults.data(forKey: "MenuBarVisibilityBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale), !stale {
                _ = url.startAccessingSecurityScopedResource()
                visibilityAuthorizedURL = url
            }
        }
        if appState != nil { restoreTemporaryVisibility() }
        spacerManager?.synchronize(activeProfile?.spacers ?? [])
    }

    deinit {
        orderVerificationTask?.cancel()
        authorizedURL?.stopAccessingSecurityScopedResource()
        visibilityAuthorizedURL?.stopAccessingSecurityScopedResource()
    }

    func refresh(captureImages shouldCaptureImages: Bool = true) async {
        guard !isScanning, !isCapturingImages else {
            if shouldCaptureImages { refreshPending = true }
            return
        }
        isScanning = true
        isRefreshing = shouldCaptureImages
        let displayID = currentDisplayID
        let automaticProfileID = displayID != lastDisplayID ? displayID.flatMap { displayID in
            profiles.first(where: { $0.automaticDisplayID == displayID })?.id
        } : nil
        lastDisplayID = displayID
        defer {
            isScanning = false
            isRefreshing = false
            if refreshPending {
                refreshPending = false
                Task { [weak self] in await self?.refresh() }
            }
            if let automaticProfileID, automaticProfileID != activeProfileID {
                Task { [weak self] in await self?.selectProfile(automaticProfileID) }
            }
        }
        var positions = try? store.positions()
        canEdit = positions != nil
        var approvals = try? visibilityStore.approvals()
        canChangeVisibility = approvals != nil
        visibility = approvals ?? [:]
        var result = await scan(applications: applications(), positions: positions ?? [:])
        // MenuBarAgent can create the preference file after the settings window opens.
        // Retry after the AX scan so a transient startup read does not leave ordering disabled.
        if positions == nil {
            positions = try? store.positions()
            canEdit = positions != nil
            if let positions { result = await scan(applications: applications(), positions: positions) }
        }
        if approvals == nil {
            approvals = try? visibilityStore.approvals()
            canChangeVisibility = approvals != nil
            visibility = approvals ?? [:]
        }
        if !Task.isCancelled {
            // A background scan must not publish an order captured before an edit.
            if !shouldCaptureImages,
               isApplying || NSEvent.pressedMouseButtons != 0 || (try? store.positions()) != positions { return }
            if let currentPositions = positions, let currentApprovals = approvals {
                do {
                    try reconcileNewApplications(result, positions: currentPositions, approvals: currentApprovals)
                    positions = try store.positions()
                    visibility = (try? visibilityStore.approvals()) ?? currentApprovals
                    if let positions {
                        result.sort {
                            let left = positions[$0.positionKey ?? "", default: 0]
                            let right = positions[$1.positionKey ?? "", default: 0]
                            return left == right ? $0.id < $1.id : left > right
                        }
                    }
                } catch { errorMessage = error.localizedDescription }
            }
            nativePositions = positions ?? [:]
            entries = result
            itemImages = appState != nil ? imageStore.images(for: result) : [:]
            if shouldCaptureImages, appState != nil, !isApplying, !isCapturingImages {
                _ = try? await captureImages(for: result)
            }
        }
    }

    private func reconcileNewApplications(_ discovered: [Entry], positions: [String: Double], approvals: [String: Bool]) throws {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        var profile = profiles[index]
        let baseline = profile.positions.isEmpty
        let fresh = discovered.filter { entry in
            guard let key = entry.positionKey else { return false }
            return !baseline && profile.sections[entry.bundleID] == nil && profile.positions[key] == nil &&
                key.hasPrefix("status:") && approvals[entry.bundleID] != nil
        }
        let freshIDs = Set(fresh.map(\.id))
        var updated = positions
        var changed = [String: Bool]()
        do {
            let placement = profile.newItemPlacement
            let existing = displayEntries(in: placement.section).filter { !$0.isInsertionMarker && !freshIDs.contains($0.id) }
            let explicitTarget = placement.beforeID.flatMap { id in
                existing.first(where: { $0.id == id })?.positionKey ?? (positions[id] != nil ? id : nil)
            }
            var target = explicitTarget ?? existing.last?.positionKey
            let after = explicitTarget == nil
            for entry in fresh {
                if let source = entry.positionKey, let target, source != target, updated[target] != nil {
                    let keys = updated.keys.filter { $0.hasPrefix("status:") || $0.hasPrefix("module:") }.sorted {
                        updated[$0]! == updated[$1]! ? $0 < $1 : updated[$0]! > updated[$1]!
                    }
                    updated = try MenuBarPositionStore.reordered(updated, keys: keys, moving: source, before: target, after: after)
                }
                if after { target = entry.positionKey }
                // Every item of a newly seen application shares the native approval.
                if changed[entry.bundleID] == nil, let original = approvals[entry.bundleID], original != (placement.section == .visible) {
                    try visibilityStore.setAllowed(placement.section == .visible, for: entry.bundleID, replacing: original)
                    changed[entry.bundleID] = original
                }
                profile.sections[entry.bundleID] = placement.section
            }
            if updated != positions { try store.save(updated, replacing: positions) }
        } catch {
            var message = error.localizedDescription
            for (bundle, original) in changed {
                do { try visibilityStore.setAllowed(original, for: bundle, replacing: !original) }
                catch { message += "\n" + error.localizedDescription }
            }
            throw NSError(domain: "Ice.MenuBarPlacement", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        for entry in discovered where entry.positionKey != nil && profile.sections[entry.bundleID] == nil {
            profile.sections[entry.bundleID] = approvals[entry.bundleID] == false ? .hidden : .visible
        }
        if baseline || !fresh.isEmpty {
            profile.positions.merge(updated) { _, new in new }
        } else {
            for entry in discovered {
                if let key = entry.positionKey, profile.positions[key] == nil, let position = positions[key] {
                    profile.positions[key] = position
                }
            }
        }
        if !fresh.isEmpty { canUndo = false; notice = nil }
        if profiles[index] != profile {
            profiles[index] = profile
            saveProfiles()
        }
    }

    func recaptureImages() async {
        guard !isBusy, hideHiddenItems() else { return }
        isCapturingImages = true
        errorMessage = nil
        defer { isCapturingImages = false }
        do {
            var captured = try await captureCurrentImages()
            let approvals = try visibilityStore.approvals()
            let hiddenBundles = Set(entries.filter { approvals[$0.bundleID] == false }.map(\.bundleID))
            var missing = false
            for bundleID in hiddenBundles.sorted() {
                try Task.checkCancellation()
                let fresh = try await visibilityStore.withTemporaryVisibility(for: bundleID) {
                    // MenuBarAgent finishes drawing a newly allowed item after its slide/fade.
                    try await Task.sleep(for: .milliseconds(600))
                    return try await self.captureCurrentImages(bundleID: bundleID)
                }
                let bundleEntries = Set(entries.filter { $0.bundleID == bundleID }.map(\.id))
                missing = missing || bundleEntries.isDisjoint(with: fresh)
                captured.formUnion(fresh)
            }
            if captured.isEmpty { throw ModernMenuBarImageStore.Failure.noImages }
            if missing { throw ModernMenuBarImageStore.Failure.incomplete }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreTemporaryVisibility() {
        do { try visibilityStore.restoreTemporaryVisibility() }
        catch { errorMessage = error.localizedDescription }
        _ = hideHiddenItems()
    }

    @discardableResult
    func showHiddenItems() -> Bool {
        guard !isBusy else { return false }
        guard !areHiddenItemsRevealed else { return true }
        let hidden = Set((activeProfile?.sections ?? [:]).filter { $0.value == .hidden }.map(\.key))
            .union(entries.filter { section(for: $0) == .hidden }.map(\.bundleID))
        do {
            let approvals = try revealVisibilityStore.approvals()
            for bundle in hidden.sorted() where approvals[bundle] == false {
                try revealVisibilityStore.beginTemporaryVisibility(for: bundle)
            }
            areHiddenItemsRevealed = true
            synchronizeSpacers()
            return true
        } catch {
            var message = error.localizedDescription
            do { try revealVisibilityStore.restoreTemporaryVisibility() }
            catch { message += "\n" + error.localizedDescription }
            errorMessage = message
            return false
        }
    }

    @discardableResult
    func hideHiddenItems() -> Bool {
        do {
            try revealVisibilityStore.restoreTemporaryVisibility()
            if areHiddenItemsRevealed {
                areHiddenItemsRevealed = false
                synchronizeSpacers()
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func authorize() {
        let panel = NSOpenPanel()
        panel.message = AppLanguage.localized("Choose the menu bar preferences file to allow arranging items.")
        panel.directoryURL = store.url.deletingLastPathComponent()
        panel.nameFieldStringValue = "com.apple.MenuBar.plist"
        panel.allowedContentTypes = [.propertyList]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            guard url.lastPathComponent == "com.apple.MenuBar.plist" else {
                errorMessage = AppLanguage.localized("Choose the menu bar preferences file to allow arranging items.")
                return
            }
            let accessing = url.startAccessingSecurityScopedResource()
            do {
                let candidate = MenuBarPositionStore(url: url, backupURL: store.backupURL)
                _ = try candidate.positions()
                let bookmark = try url.bookmarkData(options: .withSecurityScope)
                authorizedURL?.stopAccessingSecurityScopedResource()
                authorizedURL = url
                defaults.set(bookmark, forKey: "MenuBarLayoutBookmark")
                Task { await self.refresh() }
            } catch {
                if accessing { url.stopAccessingSecurityScopedResource() }
                errorMessage = error.localizedDescription
            }
        }
    }

    func authorizeVisibility() {
        let panel = NSOpenPanel()
        panel.message = AppLanguage.localized("Choose the Control Center preferences file to manage hidden items.")
        panel.directoryURL = visibilityStore.url.deletingLastPathComponent()
        panel.nameFieldStringValue = "group.com.apple.controlcenter.plist"
        panel.allowedContentTypes = [.propertyList]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            guard url.lastPathComponent == "group.com.apple.controlcenter.plist" else {
                errorMessage = AppLanguage.localized("Choose the Control Center preferences file to manage hidden items.")
                return
            }
            let accessing = url.startAccessingSecurityScopedResource()
            do {
                let candidate = MenuBarVisibilityStore(url: url, backupURL: visibilityStore.backupURL)
                _ = try candidate.approvals()
                let bookmark = try url.bookmarkData(options: .withSecurityScope)
                visibilityAuthorizedURL?.stopAccessingSecurityScopedResource()
                visibilityAuthorizedURL = url
                defaults.set(bookmark, forKey: "MenuBarVisibilityBookmark")
                Task { await self.refresh() }
            } catch {
                if accessing { url.stopAccessingSecurityScopedResource() }
                errorMessage = error.localizedDescription
            }
        }
    }

    func move(_ sourceID: String, before targetID: String, after: Bool = false) async {
        guard let source = entries.first(where: { $0.id == sourceID }),
              let target = entries.first(where: { $0.id == targetID }), sourceID != targetID else { return }
        _ = await applyLayout(source: source, target: target, after: after)
    }

    @discardableResult
    private func applyLayout(source: Entry, target: Entry? = nil, after: Bool = false,
                             section: MenuBarLayoutSection? = nil, layout: MenuBarLayoutProfile? = nil) async -> Bool {
        guard !isBusy, canEdit, let sourceKey = source.positionKey, hideHiddenItems() else { return false }
        isApplying = true
        errorMessage = nil
        orderVerificationTask?.cancel()
        defer { isApplying = false }
        var original: [String: Double]?
        var written: [String: Double]?
        var visibilityChange: (before: Bool, after: Bool)?
        do {
            let positions = try store.positions()
            original = positions
            let discoveredOrder = (entries.compactMap(\.positionKey) +
                (activeProfile?.spacers.map { MenuBarSpacerManager.positionKey(for: $0.id) } ?? []))
                .filter { positions[$0] != nil }
            let orderIndex = Dictionary(uniqueKeysWithValues: discoveredOrder.enumerated().map { ($1, $0) })
            let keys = discoveredOrder.sorted {
                let left = positions[$0, default: 0]
                let right = positions[$1, default: 0]
                return left == right
                    ? orderIndex[$0, default: 0] < orderIndex[$1, default: 0]
                    : left > right
            }
            var updated = positions
            if let targetKey = target?.positionKey, sourceKey != targetKey {
                updated = try MenuBarPositionStore.reordered(positions, keys: keys, moving: sourceKey, before: targetKey, after: after)
            }
            var sections = activeProfile?.sections ?? [:]
            let changesSection = section.map { $0 != self.section(for: source) } ?? false
            var approval: Bool?
            if changesSection, let section {
                guard !sourceKey.hasPrefix("module:"), let allowed = try visibilityStore.approvals()[source.bundleID] else {
                    throw MenuBarVisibilityStore.Failure.unidentified
                }
                approval = allowed
                sections[source.bundleID] = section
            }
            var plannedLayout = layout
            if plannedLayout == nil, target != nil || changesSection {
                let destinationSection = section ?? self.section(for: source)
                let destination = displayEntries(in: destinationSection).filter { $0.id != source.id }
                var beforeID = target?.id
                if after, let targetIndex = destination.firstIndex(where: { $0.id == beforeID }) {
                    beforeID = destination.dropFirst(targetIndex + 1).first?.id
                }
                plannedLayout = layoutAfterDrop(source.id, in: destinationSection, before: beforeID)
            }
            let changesPlacement = plannedLayout.map {
                $0.spacers != activeProfile?.spacers || $0.newItemPlacement != activeProfile?.newItemPlacement
            } ?? false
            guard positions != updated || changesSection || changesPlacement else { return true }
            if positions != updated {
                try store.save(updated, replacing: positions)
                written = updated
            }
            if let approval, let section, approval != (section == .visible) {
                let desired = section == .visible
                try visibilityStore.setAllowed(desired, for: source.bundleID, replacing: approval)
                visibilityChange = (approval, desired)
            }
            previousPositions = positions
            writtenPositions = updated
            previousSections = activeProfile?.sections
            previousProfiles = profiles
            previousActiveProfileID = activeProfileID
            previousVisibility = visibilityChange.map { [source.bundleID: $0.before] } ?? [:]
            writtenVisibility = visibilityChange.map { [source.bundleID: $0.after] } ?? [:]
            canUndo = true
            notice = AppLanguage.localized("Menu bar layout updated.")
            if let plannedLayout, let index = profiles.firstIndex(where: { $0.id == activeProfileID }) {
                profiles[index].spacers = plannedLayout.spacers
                profiles[index].newItemPlacement = plannedLayout.newItemPlacement
            }
            updateActiveProfile(positions: updated, sections: sections)
            await refresh()
            if let target, !target.isSpacer, positions != updated {
                orderVerificationTask = Task { [weak self] in
                    guard let self else { return }
                    let applied = await verifyOrder(source: source, target: target, after: after)
                    if applied && !Task.isCancelled { notice = AppLanguage.localized("Menu bar order updated.") }
                }
            }
            return true
        } catch {
            var message = error.localizedDescription
            if let change = visibilityChange {
                do { try visibilityStore.setAllowed(change.before, for: source.bundleID, replacing: change.after) }
                catch { message += "\n" + error.localizedDescription }
            }
            if let original, let written {
                do { try store.save(original, replacing: written) }
                catch { message += "\n" + error.localizedDescription }
            }
            errorMessage = message
            await refresh()
            return false
        }
    }

    func undo() async {
        guard !isBusy, canUndo, hideHiddenItems() else { return }
        guard let previousPositions, let writtenPositions else { return }
        isApplying = true
        defer { isApplying = false }
        var restoredPositions = false
        var restoredVisibility = [String: Bool]()
        do {
            if !previousVisibility.isEmpty {
                let approvals = try visibilityStore.approvals()
                guard writtenVisibility.allSatisfy({ approvals[$0.key] == $0.value }) else {
                    throw MenuBarVisibilityStore.Failure.changed
                }
            }
            guard try store.positions() == writtenPositions else { throw MenuBarPositionStore.Failure.changed }
            if let previousProfiles {
                spacerManager?.synchronize(previousProfiles.first(where: { $0.id == previousActiveProfileID })?.spacers ?? [])
            }
            if previousPositions != writtenPositions {
                try store.save(previousPositions, replacing: writtenPositions)
                restoredPositions = true
            }
            for (bundle, allowed) in previousVisibility {
                guard let expected = writtenVisibility[bundle] else { continue }
                try visibilityStore.setAllowed(allowed, for: bundle, replacing: expected)
                restoredVisibility[bundle] = allowed
            }
            if let previousProfiles {
                profiles = previousProfiles
                activeProfileID = previousActiveProfileID
                saveProfiles()
            } else {
                updateActiveProfile(positions: previousPositions, sections: previousSections)
            }
            self.previousPositions = nil
            self.writtenPositions = nil
            self.previousSections = nil
            self.previousProfiles = nil
            previousActiveProfileID = nil
            previousVisibility = [:]
            writtenVisibility = [:]
            canUndo = false
            notice = nil
            await refresh()
        } catch {
            var message = error.localizedDescription
            for (bundle, allowed) in restoredVisibility {
                guard let written = writtenVisibility[bundle] else { continue }
                do { try visibilityStore.setAllowed(written, for: bundle, replacing: allowed) }
                catch { message += "\n" + error.localizedDescription }
            }
            spacerManager?.synchronize(activeProfile?.spacers ?? [])
            if restoredPositions {
                do { try store.save(writtenPositions, replacing: previousPositions) }
                catch { message += "\n" + error.localizedDescription }
            }
            errorMessage = message
        }
    }

    func moveLeft(_ id: String) async {
        let movable = entries.filter { $0.positionKey != nil }
        guard let index = movable.firstIndex(where: { $0.id == id }), index > 0 else { return }
        await move(id, before: movable[index - 1].id)
    }

    func moveRight(_ id: String) async {
        let movable = entries.filter { $0.positionKey != nil }
        guard let index = movable.firstIndex(where: { $0.id == id }), index + 1 < movable.count else { return }
        await move(movable[index + 1].id, before: id)
    }

    func canMoveLeft(_ id: String) -> Bool {
        let movable = entries.filter { $0.positionKey != nil }
        guard let index = movable.firstIndex(where: { $0.id == id }) else { return false }
        return index > 0 && canEdit && !isRefreshing
    }

    func canMoveRight(_ id: String) -> Bool {
        let movable = entries.filter { $0.positionKey != nil }
        guard let index = movable.firstIndex(where: { $0.id == id }) else { return false }
        return index + 1 < movable.count && canEdit && !isRefreshing
    }

    func section(for entry: Entry) -> MenuBarLayoutSection {
        activeProfile?.sections[entry.bundleID] ?? (visibility[entry.bundleID] == false ? .hidden : .visible)
    }

    func entries(in section: MenuBarLayoutSection) -> [Entry] {
        entries.filter { $0.positionKey != nil && self.section(for: $0) == section }
    }

    func displayEntries(in section: MenuBarLayoutSection) -> [Entry] {
        var result = entries(in: section)
        var pending = [(Entry, String?)]()
        for spacer in activeProfile?.spacers.filter({ $0.section == section }) ?? [] {
            let id = "spacer:\(spacer.id.uuidString)"
            let entry = Entry(
                id: id, name: spacer.content == .text && !spacer.trimmedText.isEmpty
                    ? spacer.trimmedText : AppLanguage.localized("Spacer"), bundleID: Constants.bundleIdentifier,
                pid: getpid(), frame: .zero, positionKey: MenuBarSpacerManager.positionKey(for: spacer.id), identifier: id, nativeTitle: "",
                isVisible: spacer.section == .visible, spacer: spacer
            )
            if nativePositions[entry.positionKey ?? ""] != nil {
                result.append(entry)
            } else {
                pending.append((entry, spacer.beforeID))
            }
        }
        let orderIndex = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($1.id, $0) })
        result.sort {
            let left = nativePositions[$0.positionKey ?? "", default: 0]
            let right = nativePositions[$1.positionKey ?? "", default: 0]
            return left == right ? orderIndex[$0.id, default: 0] < orderIndex[$1.id, default: 0] : left > right
        }
        // Unregistered hidden spacers still need their saved anchors, including spacer chains.
        while !pending.isEmpty {
            let next = pending.firstIndex { _, beforeID in
                beforeID == nil || result.contains(where: { $0.id == beforeID })
            } ?? 0
            let (entry, beforeID) = pending.remove(at: next)
            let index = beforeID.flatMap { id in result.firstIndex(where: { $0.id == id }) } ?? result.endIndex
            result.insert(entry, at: index)
        }
        if let placement = activeProfile?.newItemPlacement, placement.section == section {
            let marker = Entry(id: Entry.insertionMarkerID, name: AppLanguage.localized("New Items\nhere"),
                               bundleID: Constants.bundleIdentifier, pid: getpid(), frame: .zero, positionKey: nil,
                               identifier: Entry.insertionMarkerID, nativeTitle: "", isVisible: false)
            if let beforeID = placement.beforeID, let index = result.firstIndex(where: { $0.id == beforeID }) {
                result.insert(marker, at: index)
            } else { result.append(marker) }
        }
        return result
    }

    @discardableResult
    func setSection(_ section: MenuBarLayoutSection, for entry: Entry) async -> Bool {
        await applyLayout(source: entry, section: section)
    }

    func drop(_ sourceID: String, in section: MenuBarLayoutSection, before targetID: String?) async {
        guard !isBusy, hideHiddenItems() else { return }
        errorMessage = nil
        let destination = displayEntries(in: section)
        guard targetID == nil || destination.contains(where: { $0.id == targetID }) else {
            errorMessage = MenuBarPositionStore.Failure.changed.localizedDescription
            return
        }
        guard sourceID != targetID else { return }
        if sourceID == Entry.insertionMarkerID {
            do {
                let positions = try store.positions()
                guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
                previousPositions = positions
                writtenPositions = positions
                previousProfiles = profiles
                previousActiveProfileID = activeProfileID
                previousVisibility = [:]
                writtenVisibility = [:]
                if let layout = layoutAfterDrop(sourceID, in: section, before: targetID) {
                    profiles[index] = layout
                }
                saveProfiles()
                canUndo = true
                notice = AppLanguage.localized("Menu bar layout updated.")
            } catch { errorMessage = error.localizedDescription }
            return
        }
        if sourceID == "palette-spacer" || sourceID.hasPrefix("spacer:") {
            await addSpacer(sourceID: sourceID, in: section, before: targetID)
            return
        }
        guard let source = entries.first(where: { $0.id == sourceID }) else { return }
        let layout = layoutAfterDrop(sourceID, in: section, before: targetID)
        do {
            let positions = try store.positions()
            let isNativeTarget: (Entry) -> Bool = {
                $0.id != sourceID && $0.positionKey.map { positions[$0] != nil } == true
            }
            if let targetID, let index = destination.firstIndex(where: { $0.id == targetID }),
               let target = destination.dropFirst(index).first(where: isNativeTarget) {
                await applyLayout(source: source, target: target, section: section, layout: layout)
            } else {
                let target = destination.last(where: isNativeTarget)
                await applyLayout(source: source, target: target, after: true, section: section, layout: layout)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func layoutAfterDrop(_ sourceID: String, in section: MenuBarLayoutSection, before targetID: String?) -> MenuBarLayoutProfile? {
        guard var profile = activeProfile else { return nil }
        if sourceID == Entry.insertionMarkerID { profile.newItemPlacement.section = section }
        if let index = profile.spacers.firstIndex(where: { "spacer:\($0.id.uuidString)" == sourceID }) {
            profile.spacers[index].section = section
        }
        for area in MenuBarLayoutSection.allCases {
            var ids = displayEntries(in: area).map(\.id).filter { $0 != sourceID }
            if area == section {
                let index = targetID.flatMap { ids.firstIndex(of: $0) } ?? ids.endIndex
                ids.insert(sourceID, at: index)
            }
            for index in profile.spacers.indices where profile.spacers[index].section == area {
                if let offset = ids.firstIndex(of: "spacer:\(profile.spacers[index].id.uuidString)") {
                    profile.spacers[index].beforeID = ids.dropFirst(offset + 1).first { $0 != Entry.insertionMarkerID }
                }
            }
            if profile.newItemPlacement.section == area, let marker = ids.firstIndex(of: Entry.insertionMarkerID) {
                profile.newItemPlacement.beforeID = ids.dropFirst(marker + 1).first
            }
        }
        return profile
    }

    private func addSpacer(sourceID: String, in section: MenuBarLayoutSection, before targetID: String?) async {
        guard !isBusy, let spacerManager, let profileIndex = profiles.firstIndex(where: { $0.id == activeProfileID }),
              sourceID != targetID else { return }
        guard targetID == nil || displayEntries(in: section).contains(where: { $0.id == targetID }),
              sourceID == "palette-spacer" || activeProfile?.spacers.contains(where: { "spacer:\($0.id.uuidString)" == sourceID }) == true else {
            errorMessage = MenuBarPositionStore.Failure.changed.localizedDescription
            return
        }
        isApplying = true
        defer { isApplying = false }
        let oldProfiles = profiles
        var original: [String: Double]?
        var written: [String: Double]?
        do {
            original = try store.positions()
            let spacerID: UUID
            if let index = profiles[profileIndex].spacers.firstIndex(where: { "spacer:\($0.id.uuidString)" == sourceID }) {
                spacerID = profiles[profileIndex].spacers[index].id
            } else {
                let spacer = MenuBarLayoutSpacer(section: section)
                spacerID = spacer.id
                profiles[profileIndex].spacers.append(spacer)
            }
            if let layout = layoutAfterDrop("spacer:\(spacerID.uuidString)", in: section, before: targetID) {
                profiles[profileIndex] = layout
            }
            let anchor = profiles[profileIndex].spacers.first(where: { $0.id == spacerID })?.beforeID
            spacerManager.synchronize(activeProfile?.spacers ?? [])
            let sourceKey = MenuBarSpacerManager.positionKey(for: spacerID)
            let current = try await registeredSpacerPositions(activeProfile?.spacers ?? [])
            written = current
            if current[sourceKey] != nil {
                let candidates = displayEntries(in: section).filter { !$0.isInsertionMarker && $0.id != "spacer:\(spacerID.uuidString)" }
                let target = anchor.flatMap { id in candidates.first { $0.id == id } } ?? (anchor == nil ? candidates.last : nil)
                if let targetKey = target?.positionKey, current[targetKey] != nil {
                    let known = entries.compactMap(\.positionKey) + (activeProfile?.spacers.map { MenuBarSpacerManager.positionKey(for: $0.id) } ?? [])
                    let keys = Set(known).filter { current[$0] != nil }.sorted {
                        let left = current[$0, default: 0], right = current[$1, default: 0]
                        return left == right ? $0 < $1 : left > right
                    }
                    let next = try MenuBarPositionStore.reordered(current, keys: keys, moving: sourceKey,
                                                                 before: targetKey, after: anchor == nil)
                    if current != next { try store.save(next, replacing: current) }
                    written = next
                }
            }
            previousProfiles = oldProfiles
            previousActiveProfileID = activeProfileID
            previousPositions = original
            writtenPositions = written
            previousVisibility = [:]
            writtenVisibility = [:]
            profiles[profileIndex].positions = written ?? original ?? [:]
            saveProfiles()
            canUndo = true
            notice = AppLanguage.localized("Menu bar layout updated.")
            await refresh()
        } catch {
            let attemptedSpacers = profiles[profileIndex].spacers
            profiles = oldProfiles
            spacerManager.synchronize(activeProfile?.spacers ?? [])
            var message = error.localizedDescription
            if let original, let written {
                do { try store.save(original, replacing: written) }
                catch { message += "\n" + error.localizedDescription }
            } else if let original {
                do { try removeFailedSpacerRegistrations(attemptedSpacers, originalPositions: original) }
                catch { message += "\n" + error.localizedDescription }
            }
            errorMessage = message
        }
    }

    func updateSpacer(_ sourceID: String, to updated: MenuBarLayoutSpacer) {
        guard !isBusy, updated.width.isFinite, sourceID == "spacer:\(updated.id.uuidString)",
              let profileIndex = profiles.firstIndex(where: { $0.id == activeProfileID }),
              let index = profiles[profileIndex].spacers.firstIndex(where: { "spacer:\($0.id.uuidString)" == sourceID }) else { return }
        guard updated.content != .symbol || NSImage(systemSymbolName: updated.trimmedSymbolName, accessibilityDescription: nil) != nil else { return }
        // An open editor must not restore an old section or insertion anchor.
        profiles[profileIndex].spacers[index].width = Double(updated.validatedWidth)
        profiles[profileIndex].spacers[index].content = updated.content
        profiles[profileIndex].spacers[index].text = updated.text
        profiles[profileIndex].spacers[index].symbolName = updated.symbolName
        saveProfiles()
    }

    func removeSpacer(_ sourceID: String) {
        guard !isBusy, let profileIndex = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        let removed = profiles[profileIndex].spacers.filter { "spacer:\($0.id.uuidString)" == sourceID }
        profiles[profileIndex].spacers.removeAll { "spacer:\($0.id.uuidString)" == sourceID }
        for spacer in removed { profiles[profileIndex].positions.removeValue(forKey: MenuBarSpacerManager.positionKey(for: spacer.id)) }
        saveProfiles()
        canUndo = false
        notice = nil
    }

    func createProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        canUndo = false
        notice = nil
        profiles.append(MenuBarLayoutProfile(name: trimmed, sections: activeProfile?.sections ?? [:],
                                             positions: (try? store.positions()) ?? [:], spacers: activeProfile?.spacers ?? [],
                                             newItemPlacement: activeProfile?.newItemPlacement ?? MenuBarNewItemPlacement()))
        activeProfileID = profiles.last?.id
        saveProfiles()
    }

    func renameProfile(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmed
        canUndo = false
        notice = nil
        saveProfiles()
    }

    func setAutomaticForCurrentDisplay(_ enabled: Bool) {
        guard !isBusy, let activeProfileID, let currentDisplayID,
              let activeIndex = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        for index in profiles.indices where profiles[index].automaticDisplayID == currentDisplayID {
            profiles[index].automaticDisplayID = nil
        }
        profiles[activeIndex].automaticDisplayID = enabled ? currentDisplayID : nil
        saveProfiles()
    }

    func selectProfile(_ id: UUID) async {
        guard !isBusy, id != activeProfileID, let profile = profiles.first(where: { $0.id == id }),
              hideHiddenItems() else { return }
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        var changed = [String: (before: Bool, after: Bool)]()
        var initial: [String: Double]?
        var updated: [String: Double]?
        do {
            initial = try store.positions()
            spacerManager?.synchronize(profile.spacers)
            let positions = try await registeredSpacerPositions(profile.spacers)
            updated = positions
            let approvals = try visibilityStore.approvals()
            for (bundle, section) in profile.sections {
                guard let previous = approvals[bundle], previous != (section == .visible) else { continue }
                let desired = section == .visible
                try visibilityStore.setAllowed(desired, for: bundle, replacing: previous)
                changed[bundle] = (previous, desired)
            }
            let next = positions.merging(profile.positions.filter { positions[$0.key] != nil }) { _, new in new }
            try store.save(next, replacing: positions)
            updated = next
            previousPositions = initial
            writtenPositions = next
            previousSections = activeProfile?.sections
            previousVisibility = changed.mapValues(\.before)
            previousProfiles = profiles
            previousActiveProfileID = activeProfileID
            writtenVisibility = changed.mapValues(\.after)
            activeProfileID = id
            canUndo = true
            saveProfiles()
            await refresh()
        } catch {
            var message = error.localizedDescription
            spacerManager?.synchronize(activeProfile?.spacers ?? [])
            if let initial, let updated {
                do { try store.save(initial, replacing: updated) }
                catch { message += "\n" + error.localizedDescription }
            } else if let initial {
                do { try removeFailedSpacerRegistrations(profile.spacers, originalPositions: initial) }
                catch { message += "\n" + error.localizedDescription }
            }
            for (bundle, change) in changed {
                do { try visibilityStore.setAllowed(change.before, for: bundle, replacing: change.after) }
                catch { message += "\n" + error.localizedDescription }
            }
            errorMessage = message
            await refresh()
        }
    }

    func deleteActiveProfile() async {
        guard profiles.count > 1, let id = activeProfileID, let replacement = profiles.first(where: { $0.id != id }) else { return }
        await selectProfile(replacement.id)
        guard activeProfileID == replacement.id else { return }
        profiles.removeAll { $0.id == id }
        saveProfiles()
    }

    private func updateActiveProfile(positions: [String: Double]?, sections: [String: MenuBarLayoutSection]? = nil) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        if let positions { profiles[index].positions = positions }
        if let sections { profiles[index].sections = sections }
        saveProfiles()
    }

    private func saveProfiles() {
        synchronizeSpacers()
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: "MenuBarLayoutProfiles.v1") }
        defaults.set(activeProfileID?.uuidString, forKey: "MenuBarLayoutActiveProfile.v1")
    }

    private func synchronizeSpacers() {
        var spacers = activeProfile?.spacers ?? []
        if areHiddenItemsRevealed {
            for index in spacers.indices where spacers[index].section == .hidden {
                spacers[index].section = .visible
            }
        }
        spacerManager?.synchronize(spacers)
    }

    private func registeredSpacerPositions(_ spacers: [MenuBarLayoutSpacer]) async throws -> [String: Double] {
        let keys = spacers.filter { $0.section == .visible }.map { MenuBarSpacerManager.positionKey(for: $0.id) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var positions = try store.positions()
        // Native registration completes on a later run-loop turn.
        while !keys.allSatisfy({ positions[$0] != nil }) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(40))
            positions = try store.positions()
        }
        guard keys.allSatisfy({ positions[$0] != nil }) else { throw MenuBarPositionStore.Failure.invalidPositions }
        return positions
    }

    private func removeFailedSpacerRegistrations(_ spacers: [MenuBarLayoutSpacer], originalPositions: [String: Double]) throws {
        let introduced = Set(spacers.map { MenuBarSpacerManager.positionKey(for: $0.id) }.filter { originalPositions[$0] == nil })
        let current = try store.positions()
        let cleaned = current.filter { !introduced.contains($0.key) }
        if current != cleaned { try store.save(cleaned, replacing: current) }
    }

    private func applications() -> [ModernMenuBarDiscovery.Application] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated, let bundleID = app.bundleIdentifier else { return nil }
            return ModernMenuBarDiscovery.Application(pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName ?? bundleID)
        }
    }

    private func captureCurrentImages(bundleID: String? = nil) async throws -> Set<String> {
        let positions = (try? store.positions()) ?? [:]
        let participants = applications().filter { bundleID == nil || $0.bundleID == bundleID }
        let current = await scan(applications: participants, positions: positions)
        return try await captureImages(for: current)
    }

    private func captureImages(for current: [Entry]) async throws -> Set<String> {
        let positions = (try? store.positions()) ?? [:]
        let pids = Set(current.filter(\.isVisible).map(\.pid))
        let participants = applications().filter { pids.contains($0.pid) }
        let captured = try await imageStore.capture(current) {
            await self.scan(applications: participants, positions: positions)
        }
        itemImages = imageStore.images(for: entries)
        return captured
    }

    private func scan(applications: [ModernMenuBarDiscovery.Application], positions: [String: Double]) async -> [Entry] {
        let bands = menuBands
        let excluded = Constants.bundleIdentifier
        let discover = discover
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: discover(applications, positions, bands, excluded))
            }
        }
    }

    private func verifyOrder(source: Entry, target: Entry, after: Bool) async -> Bool {
        let participants = applications().filter { $0.pid == source.pid || $0.pid == target.pid }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            let fresh = await scan(applications: participants, positions: (try? store.positions()) ?? [:])
            if let left = fresh.first(where: { $0.positionKey == source.positionKey }),
               let right = fresh.first(where: { $0.positionKey == target.positionKey }), left.isVisible, right.isVisible {
                if after ? left.frame.minX >= right.frame.maxX - 1 : left.frame.maxX <= right.frame.minX + 1 { return true }
            }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return false }
        }
        return false
    }
}
