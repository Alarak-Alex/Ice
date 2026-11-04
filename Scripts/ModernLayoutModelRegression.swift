// Compile with the modern model, discovery, identity, profile, language and preference stores.
import Cocoa
import Combine

enum Constants { static let bundleIdentifier = "com.jordanbaird.Ice.Regression" }
extension NSScreen {
    var displayID: CGDirectDisplayID { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID }
}
@MainActor final class AppState { }

// This fixture is accessed only by the main-actor regression below.
private final class FixtureApplication: NSRunningApplication, @unchecked Sendable {
    var reads = 0
    var fixtureBundleID: String? = "com.example.fixture"
    var fixtureName = "Fixture"
    override var bundleIdentifier: String? { reads += 1; return fixtureBundleID }
    override var processIdentifier: pid_t { reads += 1; return 9999 }
    override var localizedName: String? { reads += 1; return fixtureName }
}

// Simulates MenuBarAgent registration using only the test's temporary preferences.
@MainActor final class FixtureSpacers: MenuBarSpacerManaging {
    let positions: MenuBarPositionStore
    private(set) var widths = [UUID: CGFloat]()
    private(set) var visible = Set<UUID>()
    var registersItems = true
    var registrationLimit: Int?
    var externalRegistrationKey: String?

    init(positions: MenuBarPositionStore) { self.positions = positions }

    func synchronize(_ spacers: [MenuBarLayoutSpacer]) {
        widths = Dictionary(uniqueKeysWithValues: spacers.map { ($0.id, $0.validatedWidth) })
        visible = Set(spacers.filter { $0.section == .visible }.map(\.id))
        let original = try! positions.positions()
        var updated = original
        let registering = spacers.filter { registersItems && $0.section == .visible }.prefix(registrationLimit ?? spacers.count)
        for spacer in registering {
            let key = MenuBarSpacerManager.positionKey(for: spacer.id)
            if updated[key] == nil { updated[key] = (updated.values.max() ?? 0) + 40 }
        }
        if let externalRegistrationKey { updated[externalRegistrationKey] = 9876 }
        if updated != original { try! positions.save(updated, replacing: original) }
    }
}

@main
struct ModernLayoutModelRegression {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        var applicationCache = ModernMenuBarDiscovery.ApplicationCache()
        var application: FixtureApplication? = FixtureApplication()
        weak var cachedApplication = application
        assert(applicationCache.applications([application!]).first?.name == "Fixture")
        assert(application!.reads == 3)
        assert(applicationCache.applications([application!]).first?.pid == 9999)
        assert(application!.reads == 3, "Unchanged app objects must not query Launch Services again")
        application = nil
        assert(cachedApplication != nil, "Cached metadata must retain its process identity")
        assert(applicationCache.applications([]).isEmpty)
        assert(cachedApplication == nil, "Departed applications must leave the metadata cache")
        let restarted = FixtureApplication()
        restarted.fixtureName = "Restarted"
        assert(applicationCache.applications([restarted]).first?.name == "Restarted" && restarted.reads == 3,
               "A new process object, even with the same PID, must load fresh metadata")
        let starting = FixtureApplication()
        starting.fixtureBundleID = nil
        assert(applicationCache.applications([starting]).isEmpty)
        starting.fixtureBundleID = "com.example.ready"
        assert(applicationCache.applications([starting]).first?.bundleID == "com.example.ready",
               "Unavailable application metadata must be retried")
        print("Application metadata: unchanged reads skipped, departures released, PID reuse and startup retry passed")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ice-model-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "com.jordanbaird.Ice.Regression.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacySpacerData = Data("""
        {"id":"4C94DA46-2003-407F-89EE-5B410183BCDE","section":"hidden","width":32}
        """.utf8)
        let legacySpacer = try JSONDecoder().decode(MenuBarLayoutSpacer.self, from: legacySpacerData)
        assert(legacySpacer.content == .blank && legacySpacer.width == 32 && legacySpacer.section == .hidden)
        assert(legacySpacer.text.isEmpty && legacySpacer.symbolName == "star",
               "Saved spacers without content must retain their identity and decode as blank")
        let futureSpacerData = Data(String(data: legacySpacerData, encoding: .utf8)!
            .replacingOccurrences(of: "\"width\":32", with: "\"width\":32,\"content\":\"future\"").utf8)
        let futureSpacer = try JSONDecoder().decode(MenuBarLayoutSpacer.self, from: futureSpacerData)
        assert(futureSpacer.id == legacySpacer.id && futureSpacer.content == .blank)
        let nativeSpacers = MenuBarSpacerManager()
        var nativeSpacer = MenuBarLayoutSpacer(section: .visible)
        nativeSpacers.synchronize([nativeSpacer])
        let nativeItem = nativeSpacers.items[nativeSpacer.id]!
        let nativeName = "Spacer-\(nativeSpacer.id.uuidString)"
        assert(nativeItem.autosaveName == nativeName)
        assert(nativeItem.button?.image?.size == NSSize(width: 16, height: 16),
               "A spacer must supply an explicit blank image at its configured width")
        assert(nativeItem.button?.identifier?.rawValue == nativeName)
        assert(nativeItem.button?.imagePosition == .imageOnly && nativeItem.button?.title == "")
        let originalImage = nativeItem.button?.image
        nativeSpacers.synchronize([nativeSpacer])
        assert(nativeItem.button?.image === originalImage, "Unchanged spacers must reuse their rendered content")
        nativeSpacer.beforeID = "changed-anchor"
        nativeSpacers.synchronize([nativeSpacer])
        assert(nativeItem.button?.image === originalImage, "Moving a spacer must not allocate another image")
        nativeSpacer.width = 48
        nativeSpacers.synchronize([nativeSpacer])
        assert(nativeSpacers.items[nativeSpacer.id] === nativeItem, "Resizing must retain native item identity")
        assert(nativeItem.length == 48 && nativeItem.button?.image?.size.width == 48)
        nativeSpacer.content = .text
        nativeSpacer.text = "  工作  \n"
        nativeSpacers.synchronize([nativeSpacer])
        // AppKit substitutes an internal placeholder image after clearing it.
        assert(nativeItem.button?.title == "工作")
        assert(nativeItem.button?.imagePosition == .noImage)
        nativeSpacer.content = .symbol
        nativeSpacer.symbolName = "star.fill"
        nativeSpacers.synchronize([nativeSpacer])
        assert(nativeItem.button?.title == "" && nativeItem.button?.image?.isTemplate == true)
        assert(nativeItem.button?.imagePosition == .imageOnly)
        nativeSpacer.symbolName = "ice.nonexistent.symbol"
        nativeSpacers.synchronize([nativeSpacer])
        assert(nativeItem.button?.image?.size == NSSize(width: 48, height: 16),
               "An unavailable saved symbol must retain an explicit blank native host")
        nativeSpacer.content = .blank
        nativeSpacers.synchronize([nativeSpacer])
        assert(nativeItem.button?.title == "" && nativeItem.button?.image?.size.width == 48)
        assert(nativeSpacers.items[nativeSpacer.id] === nativeItem, "Content edits must retain native identity")
        nativeSpacers.synchronize([])
        assert(nativeSpacers.items.isEmpty)
        nativeSpacers.synchronize([nativeSpacer])
        assert(nativeSpacers.items[nativeSpacer.id]?.button?.image != nil,
               "Removing a spacer must also discard cached render state before recreating its host")
        nativeSpacers.synchronize([])
        try await checkMixedOrdering(root: root, suite: suite)
        let keys = (1...3).map { "status:com.example.\($0)::Item-0" }
        let initial = Dictionary(uniqueKeysWithValues: zip(keys, [300.0, 200.0, 100.0]))
        let positionURL = root.appendingPathComponent("positions.plist")
        let visibilityURL = root.appendingPathComponent("visibility.plist")
        try PropertyListSerialization.data(fromPropertyList: ["TrailingItemPreferredPositions": initial], format: .binary, options: 0).write(to: positionURL)
        let records = (1...3).map { ["location": ["bundle": ["_0": "com.example.\($0)"]], "isAllowed": true] as [String: Any] }
        let tracked = try PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0)
        try PropertyListSerialization.data(fromPropertyList: ["trackedApplications": tracked, "unrelated": "keep"], format: .binary, options: 0).write(to: visibilityURL)
        let positions = MenuBarPositionStore(url: positionURL, backupURL: root.appendingPathComponent("order.before.plist"))
        let visibility = MenuBarVisibilityStore(url: visibilityURL, backupURL: root.appendingPathComponent("visibility.before.plist"))
        let spacers = FixtureSpacers(positions: positions)
        func currentPositions() -> [String: Double] { try! positions.positions() }
        func currentApprovals() -> [String: Bool] { try! visibility.approvals() }
        let model = ModernMenuBarLayoutModel(defaults: defaults, positionStore: positions, visibilityStore: visibility, spacerManager: spacers) { _, positions, _, _ in
            (1...3).map { number in
                ModernMenuBarEntry(id: keys[number - 1], name: "Item \(number)", bundleID: "com.example.\(number)",
                                  pid: -1, frame: .null, positionKey: keys[number - 1], identifier: "Item-0",
                                  nativeTitle: "", isVisible: false)
            }.sorted { positions[$0.id, default: 0] > positions[$1.id, default: 0] }
        }
        func currentProfiles() -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return try! encoder.encode(model.profiles)
        }
        await model.refresh()
        assert(model.canEdit && model.entries.count == 3)

        var refreshPublications = 0
        let refreshObservation = model.objectWillChange.sink { refreshPublications += 1 }
        for _ in 0..<3 { await model.refresh(captureImages: false) }
        assert(refreshPublications == 0, "Unchanged background scans must not invalidate the settings interface")
        try visibility.setAllowed(false, for: "com.example.1", replacing: true)
        await model.refresh(captureImages: false)
        assert(refreshPublications > 0, "Approval changes must publish even when discovered entries are unchanged")
        try visibility.setAllowed(true, for: "com.example.1", replacing: false)
        await model.refresh(captureImages: false)
        refreshPublications = 0
        var externalOrder = currentPositions()
        externalOrder[keys[0]] = 100
        externalOrder[keys[2]] = 300
        try positions.save(externalOrder, replacing: currentPositions())
        await model.refresh(captureImages: false)
        assert(refreshPublications > 0 && model.entries.first?.id == keys[2],
               "Suppressing redundant updates must still publish externally authored order changes")
        try positions.save(initial, replacing: externalOrder)
        await model.refresh(captureImages: false)
        refreshObservation.cancel()

        let imageDirectory = root.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = bitmap.representation(using: .png, properties: [:])!
        for key in keys.prefix(2) {
            try png.write(to: imageDirectory.appendingPathComponent(ModernMenuBarItemImages.fileName(for: key)))
        }
        try JSONSerialization.data(withJSONObject: [keys[0]: ["scale": 2], keys[1]: ["scale": 2]])
            .write(to: imageDirectory.appendingPathComponent("index.json"))
        let imageStore = ModernMenuBarImageStore(directory: imageDirectory)
        weak var departedImage: NSImage?
        weak var retainedImage: NSImage?
        autoreleasepool {
            let images = imageStore.images(for: Array(model.entries.prefix(2)))
            departedImage = images[keys[0]]
            retainedImage = images[keys[1]]
            assert(departedImage != nil && retainedImage != nil)
        }
        autoreleasepool {
            _ = imageStore.images(for: [model.entries[1]])
        }
        assert(departedImage == nil && retainedImage != nil,
               "Images of departed items must leave the resident cache while current images stay reusable")
        assert(imageStore.images(for: [model.entries[0]])[keys[0]] != nil,
               "Releasing resident images must preserve the disk cache for an application's return")

        await model.drop(keys[1], in: .hidden, before: nil)
        await model.drop(keys[2], in: .alwaysHidden, before: nil)
        let concealedProfile = currentProfiles()
        let concealedApprovals = currentApprovals()
        let concealedPositions = currentPositions()
        assert(model.showHiddenItems() && model.areHiddenItemsRevealed)
        assert(currentApprovals()["com.example.1"] == true && currentApprovals()["com.example.2"] == true)
        assert(currentApprovals()["com.example.3"] == false,
               "Revealing Hidden Items must never reveal Always Hidden Items")
        assert(currentProfiles() == concealedProfile && currentPositions() == concealedPositions,
               "Temporary reveal must preserve authored sections and native order")
        assert(model.showHiddenItems(), "Repeated show requests must be idempotent")
        assert(model.hideHiddenItems() && !model.areHiddenItemsRevealed)
        assert(currentApprovals() == concealedApprovals, "Hiding must restore the exact prior approvals")
        assert(model.showHiddenItems())
        model.restoreTemporaryVisibility()
        assert(!model.areHiddenItemsRevealed && currentApprovals() == concealedApprovals,
               "Quit/startup recovery must restore an interrupted reveal")
        assert(model.showHiddenItems())
        await model.drop(keys[1], in: .visible, before: nil)
        assert(!model.areHiddenItemsRevealed && currentApprovals()["com.example.3"] == false,
               "An arrangement edit must end temporary reveal before applying permanent visibility")
        await model.drop(keys[2], in: .visible, before: nil)
        assert(currentPositions() == initial && currentApprovals().values.allSatisfy { $0 })

        await model.drop(keys[0], in: .visible, before: keys[2])
        let right = try positions.positions()
        assert(right[keys[1]]! > right[keys[0]]! && right[keys[0]]! > right[keys[2]]!, "Moving right must apply to the native store")
        await model.undo()
        assert(currentPositions() == initial)

        await model.drop(keys[2], in: .visible, before: keys[0])
        assert(currentPositions()[keys[2]]! > currentPositions()[keys[0]]!)
        await model.undo()
        assert(currentPositions() == initial)

        await model.drop(keys[0], in: .hidden, before: nil)
        assert(currentApprovals()["com.example.1"] == false)
        assert(model.entries(in: .hidden).map(\.id) == [keys[0]])
        assert(currentPositions() == initial, "Changing an empty section must preserve order")
        await model.undo()
        assert(currentApprovals()["com.example.1"] == true)
        assert(model.entries(in: .hidden).isEmpty)

        await model.drop(keys[1], in: .hidden, before: nil)
        let sectionSnapshot = model.activeProfile!.sections
        await model.drop(keys[0], in: .hidden, before: keys[1])
        assert(currentApprovals()["com.example.1"] == false)
        await model.undo()
        assert(model.activeProfile!.sections == sectionSnapshot, "One undo must restore section metadata and visibility")
        assert(currentApprovals()["com.example.1"] == true)
        assert(currentApprovals()["com.example.2"] == false)

        let beforeMissing = try positions.positions()
        await model.drop(keys[0], in: .visible, before: "deleted-item")
        assert(model.errorMessage != nil && currentPositions() == beforeMissing)

        model.setAutomaticForCurrentDisplay(true)
        model.createProfile(named: "Manual choice")
        let manual = model.activeProfileID
        await model.refresh()
        assert(model.activeProfileID == manual, "Refresh must not override a manual profile selection on the same display")

        let shownProfile = model.activeProfileID!
        model.createProfile(named: "Hidden choice")
        let hiddenProfile = model.activeProfileID!
        await model.drop(keys[0], in: .hidden, before: nil)
        await model.selectProfile(shownProfile)
        assert(currentApprovals()["com.example.1"] == true, "A profile must remember shown items as well as hidden items")
        await model.selectProfile(hiddenProfile)
        assert(currentApprovals()["com.example.1"] == false)
        await model.undo()
        assert(model.activeProfileID == shownProfile && currentApprovals()["com.example.1"] == true)

        let profilesBeforeFailure = currentProfiles()
        let positionsBeforeFailure = currentPositions()
        spacers.registersItems = false
        await model.drop("palette-spacer", in: .visible, before: keys[0])
        assert(model.errorMessage != nil, "Missing native registration must be reported")
        assert(currentProfiles() == profilesBeforeFailure)
        assert(currentPositions() == positionsBeforeFailure && spacers.visible.isEmpty,
               "A failed registration must restore metadata and native hosts")
        spacers.registersItems = true
        await model.drop("spacer:\(UUID())", in: .visible, before: keys[0])
        assert(currentProfiles() == profilesBeforeFailure, "A stale spacer drag must not create a new spacer")
        await model.drop("palette-spacer", in: .visible, before: "deleted-item")
        assert(currentProfiles() == profilesBeforeFailure, "A stale spacer target must not append a spacer")

        let beforeSpacer = currentPositions()
        await model.drop("palette-spacer", in: .visible, before: keys[0])
        assert(model.errorMessage == nil)
        let spacer = model.activeProfile!.spacers.first!
        let sourceID = "spacer:\(spacer.id.uuidString)"
        let spacerKey = MenuBarSpacerManager.positionKey(for: spacer.id)
        assert(spacers.visible.contains(spacer.id) && currentPositions()[spacerKey] != nil)
        assert(currentPositions()[spacerKey]! > currentPositions()[keys[0]]!)
        var editedSpacer = spacer
        editedSpacer.width = 900
        model.updateSpacer(sourceID, to: editedSpacer)
        assert(spacers.widths[spacer.id] == 200)
        editedSpacer.width = 48
        model.updateSpacer(sourceID, to: editedSpacer)
        assert(spacers.widths[spacer.id] == 48)
        editedSpacer.width = .nan
        model.updateSpacer(sourceID, to: editedSpacer)
        assert(spacers.widths[spacer.id] == 48, "Invalid widths must not reach the native host")
        editedSpacer.width = 48
        editedSpacer.content = .text
        editedSpacer.text = "Work"
        editedSpacer.section = .hidden
        editedSpacer.beforeID = "stale-anchor"
        model.updateSpacer(sourceID, to: editedSpacer)
        assert(model.activeProfile!.spacers[0].section == .visible && model.activeProfile!.spacers[0].beforeID == spacer.beforeID,
               "An old editor value must not overwrite a spacer's current section or insertion anchor")
        let editedEntry = model.displayEntries(in: .visible).first(where: { $0.id == sourceID })
        assert(editedEntry?.spacer?.text == "Work" && editedEntry?.name == "Work",
               "A text spacer must expose its content to accessibility and tooltips")
        editedSpacer.content = .symbol
        editedSpacer.symbolName = "star.fill"
        model.updateSpacer(sourceID, to: editedSpacer)
        let savedSymbolProfiles = currentProfiles()
        editedSpacer.symbolName = "ice.nonexistent.symbol"
        model.updateSpacer(sourceID, to: editedSpacer)
        assert(currentProfiles() == savedSymbolProfiles, "Invalid symbols must not replace saved content")
        editedSpacer.id = UUID()
        model.updateSpacer(sourceID, to: editedSpacer)
        assert(currentProfiles() == savedSymbolProfiles, "An editor cannot change another spacer's identity")
        let reloadedContentModel = ModernMenuBarLayoutModel(defaults: defaults, positionStore: positions, visibilityStore: visibility)
        assert(reloadedContentModel.activeProfile!.spacers[0].content == .symbol &&
               reloadedContentModel.activeProfile!.spacers[0].symbolName == "star.fill")
        await model.undo()
        assert(model.activeProfile!.spacers.isEmpty && spacers.visible.isEmpty)
        assert(currentPositions() == beforeSpacer, "Undo must remove a newly registered spacer position")

        let noSpacerProfile = model.activeProfileID!
        model.createProfile(named: "Native spacer position")
        await model.drop("palette-spacer", in: .visible, before: keys[0])
        let retained = model.activeProfile!.spacers.first!
        let retainedID = "spacer:\(retained.id.uuidString)"
        let retainedKey = MenuBarSpacerManager.positionKey(for: retained.id)
        let retainedProfile = model.activeProfileID!
        let savedPosition = currentPositions()[retainedKey]
        await model.selectProfile(noSpacerProfile)
        var withoutSpacer = currentPositions()
        withoutSpacer.removeValue(forKey: retainedKey)
        try positions.save(withoutSpacer, replacing: currentPositions())
        await model.selectProfile(retainedProfile)
        assert(currentPositions()[retainedKey] == savedPosition,
               "Profile selection must register native spacers before restoring their saved positions")
        var retainedEdit = retained
        retainedEdit.width = 48
        retainedEdit.content = .text
        retainedEdit.text = "Focus"
        model.updateSpacer(retainedID, to: retainedEdit)
        let originalProfile = model.activeProfileID!
        model.createProfile(named: "Copied spacer")
        let copiedProfile = model.activeProfileID!
        assert(model.activeProfile!.spacers.first!.id == retained.id, "Copied configurations must retain their spacers")
        retainedEdit.width = 32
        retainedEdit.content = .symbol
        retainedEdit.symbolName = "moon.fill"
        model.updateSpacer(retainedID, to: retainedEdit)
        await model.selectProfile(originalProfile)
        assert(spacers.widths[retained.id] == 48)
        assert(model.activeProfile!.spacers[0].content == .text && model.activeProfile!.spacers[0].text == "Focus")
        await model.undo()
        assert(model.activeProfileID == copiedProfile && spacers.widths[retained.id] == 32)
        assert(model.activeProfile!.spacers[0].content == .symbol && model.activeProfile!.spacers[0].symbolName == "moon.fill")
        await model.deleteActiveProfile()
        assert(!model.profiles.contains { $0.id == copiedProfile })
        await model.undo()
        assert(model.activeProfileID == copiedProfile && spacers.widths[retained.id] == 32)
        model.removeSpacer(retainedID)
        assert(model.activeProfile!.spacers.isEmpty && spacers.visible.isEmpty)

        let beforeStaleOperation = currentPositions()
        await model.drop(keys[2], in: .hidden, before: keys[1])
        assert(currentPositions() != beforeStaleOperation, "The stale undo fixture must change both order and visibility")
        let beforeFailedUndo = currentPositions()
        let beforeFailedSections = model.activeProfile!.sections
        try visibility.setAllowed(true, for: "com.example.3", replacing: false)
        await model.undo()
        assert(model.errorMessage != nil)
        assert(currentPositions() == beforeFailedUndo && model.activeProfile!.sections == beforeFailedSections,
               "A stale visibility undo must not partially restore order or profile metadata")
        assert(currentApprovals()["com.example.3"] == true)

        model.createProfile(named: "Before registration")
        let beforeRegistrationProfile = model.activeProfileID!
        model.createProfile(named: "Two native spacers")
        await model.drop("palette-spacer", in: .visible, before: keys[0])
        await model.drop("palette-spacer", in: .visible, before: keys[0])
        let twoSpacerProfile = model.activeProfileID!
        let twoSpacerKeys = Set(model.activeProfile!.spacers.map { MenuBarSpacerManager.positionKey(for: $0.id) })
        await model.selectProfile(beforeRegistrationProfile)
        let beforeRemovingKeys = currentPositions()
        try positions.save(beforeRemovingKeys.filter { !twoSpacerKeys.contains($0.key) }, replacing: beforeRemovingKeys)
        let beforePartialRegistration = currentPositions()
        let profilesBeforePartialRegistration = currentProfiles()
        spacers.registrationLimit = 1
        let externalKey = "status:com.example.new-application::Item-0"
        spacers.externalRegistrationKey = externalKey
        await model.selectProfile(twoSpacerProfile)
        assert(model.errorMessage != nil && model.activeProfileID == beforeRegistrationProfile)
        assert(currentProfiles() == profilesBeforePartialRegistration && spacers.visible.isEmpty)
        var expectedAfterFailure = beforePartialRegistration
        expectedAfterFailure[externalKey] = 9876
        assert(currentPositions() == expectedAfterFailure,
               "Partial failure must remove its new keys while preserving a concurrently registered application")

        enum CaptureFailure: Error { case failed }
        try visibility.setAllowed(false, for: "com.example.1", replacing: true)
        do {
            _ = try await visibility.withTemporaryVisibility(for: "com.example.1") {
                assert(currentApprovals()["com.example.1"] == true)
                throw CaptureFailure.failed
            }
            assertionFailure("The capture error must reach the caller")
        } catch CaptureFailure.failed { }
        assert(currentApprovals()["com.example.1"] == false, "A capture failure must restore hidden state")
        let captured = try await visibility.withTemporaryVisibility(for: "com.example.1") {
            assert(currentApprovals()["com.example.1"] == true)
            return 7
        }
        assert(captured == 7 && currentApprovals()["com.example.1"] == false)
        let beforeOtherCapture = currentApprovals()
        try await visibility.withTemporaryVisibility(for: "com.example.2") {
            assert(currentApprovals()["com.example.2"] == true)
        }
        assert(currentApprovals() == beforeOtherCapture, "Other applications' approvals must remain unchanged")
        do {
            try await visibility.withTemporaryVisibility(for: "com.example.1") { throw CancellationError() }
        } catch is CancellationError { }
        assert(currentApprovals()["com.example.1"] == false, "Cancellation must restore hidden state")
        assert(!FileManager.default.fileExists(atPath: visibility.temporaryVisibilityJournalURL.path))
        try PropertyListEncoder().encode(["com.example.1": false]).write(to: visibility.temporaryVisibilityJournalURL)
        try visibility.setAllowed(true, for: "com.example.1", replacing: false)
        let beforeRecovery = currentApprovals()
        try visibility.restoreTemporaryVisibility()
        var expectedRecovery = beforeRecovery
        expectedRecovery["com.example.1"] = false
        assert(currentApprovals() == expectedRecovery, "Relaunch recovery must restore only the interrupted capture")
        assert(!FileManager.default.fileExists(atPath: visibility.temporaryVisibilityJournalURL.path))
        for key in keys { await model.drop(key, in: .visible, before: nil) }
        let markerID = ModernMenuBarEntry.insertionMarkerID
        assert(model.displayEntries(in: .hidden).filter(\.isInsertionMarker).count == 1)
        let markerPositions = currentPositions(), markerApprovals = currentApprovals()
        await model.drop(markerID, in: .visible, before: keys[1])
        assert(model.activeProfile!.newItemPlacement == MenuBarNewItemPlacement(section: .visible, beforeID: keys[1]))
        assert(currentPositions() == markerPositions && currentApprovals() == markerApprovals,
               "Dragging the insertion marker must not move or activate a real menu item")
        await model.undo()
        assert(model.activeProfile!.newItemPlacement == MenuBarNewItemPlacement())
        await model.drop(markerID, in: .visible, before: keys[1])
        await model.drop(keys[0], in: .visible, before: keys[1])
        assert(model.activeProfile!.newItemPlacement.beforeID == keys[0],
               "Dropping after the marker must leave the marker before the moved item")
        await model.undo()
        assert(model.activeProfile!.newItemPlacement.beforeID == keys[1])
        await model.drop("palette-spacer", in: .visible, before: keys[1])
        let markerSpacerID = "spacer:\(model.activeProfile!.spacers.last!.id.uuidString)"
        assert(model.activeProfile!.newItemPlacement.beforeID == markerSpacerID,
               "Dropping a spacer after the marker must keep the marker before that spacer")
        await model.undo()
        assert(model.activeProfile!.newItemPlacement.beforeID == keys[1])
        let markerProfile = model.activeProfileID!
        model.createProfile(named: "Copied insertion")
        assert(model.activeProfile!.newItemPlacement.beforeID == keys[1])
        await model.drop(markerID, in: .alwaysHidden, before: nil)
        await model.selectProfile(markerProfile)
        assert(model.activeProfile!.newItemPlacement.section == .visible)
        await model.undo()
        assert(model.activeProfile!.newItemPlacement.section == .alwaysHidden)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(model.activeProfile!)) as! [String: Any]
        legacy.removeValue(forKey: "newItemPlacement")
        let migrated = try JSONDecoder().decode(MenuBarLayoutProfile.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(migrated.newItemPlacement == MenuBarNewItemPlacement() && migrated.positions == model.activeProfile!.positions)

        let placementDefaults = UserDefaults(suiteName: suite + ".placement")!
        defer { placementDefaults.removePersistentDomain(forName: suite + ".placement") }
        let placementURL = root.appendingPathComponent("placement-order.plist")
        let approvalURL = root.appendingPathComponent("placement-approval.plist")
        try PropertyListSerialization.data(fromPropertyList: ["TrailingItemPreferredPositions": initial], format: .binary, options: 0).write(to: placementURL)
        try PropertyListSerialization.data(fromPropertyList: ["trackedApplications": tracked, "unrelated": "keep"], format: .binary, options: 0).write(to: approvalURL)
        let placementStore = MenuBarPositionStore(url: placementURL, backupURL: root.appendingPathComponent("placement.before.plist"))
        let approvalStore = MenuBarVisibilityStore(url: approvalURL, backupURL: root.appendingPathComponent("approval.before.plist"))
        let placementModel = ModernMenuBarLayoutModel(defaults: placementDefaults, positionStore: placementStore, visibilityStore: approvalStore) { _, positions, _, _ in
            positions.keys.sorted().compactMap { key in
                guard key.hasPrefix("status:com.example."), let bundle = key.split(separator: ":").dropFirst().first else { return nil }
                return ModernMenuBarEntry(id: key, name: key, bundleID: String(bundle), pid: -1, frame: .null,
                                          positionKey: key, identifier: "Item-0", nativeTitle: "", isVisible: false)
            }.sorted { positions[$0.id]! > positions[$1.id]! }
        }
        await placementModel.refresh()
        let migratedApprovals = try approvalStore.approvals()
        assert(migratedApprovals.values.allSatisfy { $0 }, "Existing applications must retain their approvals on migration")
        await placementModel.drop(markerID, in: .visible, before: keys[1])
        func register(_ number: Int, position: Double) throws -> String {
            let bundle = "com.example.\(number)"
            let key = "status:\(bundle)::Item-0"
            let before = try placementStore.positions()
            var updated = before
            updated[key] = position
            try placementStore.save(updated, replacing: before)
            var root = try PropertyListSerialization.propertyList(from: Data(contentsOf: approvalURL), format: nil) as! [String: Any]
            var records = try PropertyListSerialization.propertyList(from: root["trackedApplications"] as! Data, format: nil) as! [[String: Any]]
            records.append(["location": ["bundle": ["_0": bundle]], "isAllowed": true])
            root["trackedApplications"] = try PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0)
            try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0).write(to: approvalURL)
            return key
        }
        let fourth = try register(4, position: 500)
        await placementModel.refresh(captureImages: false)
        let fourthPositions = try placementStore.positions()
        assert(fourthPositions[keys[0]]! > fourthPositions[fourth]! && fourthPositions[fourth]! > fourthPositions[keys[1]]!)
        assert(placementModel.activeProfile!.sections["com.example.4"] == .visible)
        await placementModel.drop(keys[2], in: .hidden, before: nil)
        await placementModel.drop(markerID, in: .hidden, before: keys[2])
        let fifth = try register(5, position: 600)
        await placementModel.refresh(captureImages: false)
        let fifthApprovals = try approvalStore.approvals()
        assert(fifthApprovals["com.example.5"] == false)
        assert(placementModel.entries(in: .hidden).contains { $0.id == fifth })
        let fifthPositions = try placementStore.positions()
        assert(fifthPositions[fifth]! > fifthPositions[keys[2]]!)
        let afterPlacement = try placementStore.positions()
        await placementModel.refresh(captureImages: false)
        let afterRepeatedScan = try placementStore.positions()
        assert(afterRepeatedScan == afterPlacement, "Repeated scans must not move an already authored application")
        let reloadedPlacement = ModernMenuBarLayoutModel(defaults: placementDefaults, positionStore: placementStore, visibilityStore: approvalStore)
        assert(reloadedPlacement.activeProfile!.newItemPlacement == placementModel.activeProfile!.newItemPlacement)
        assert(reloadedPlacement.activeProfile!.positions[fourth] != nil && reloadedPlacement.activeProfile!.sections["com.example.5"] == .hidden)
        let (scanStarted, signalScanStarted) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let finishScan = DispatchSemaphore(value: 0)
        let backgroundModel = ModernMenuBarLayoutModel(defaults: placementDefaults, positionStore: placementStore, visibilityStore: approvalStore) { _, _, _, _ in
            signalScanStarted.yield(())
            signalScanStarted.finish()
            _ = finishScan.wait(timeout: .now() + 2)
            return [ModernMenuBarEntry(id: keys[0], name: "Old scan", bundleID: "com.example.1", pid: -1, frame: .null,
                                       positionKey: keys[0], identifier: "", nativeTitle: "", isVisible: false)]
        }
        let backgroundRefresh = Task { await backgroundModel.refresh(captureImages: false) }
        for await _ in scanStarted { break }
        assert(!backgroundModel.isRefreshing && !backgroundModel.isBusy, "Background scanning must leave the editor interactive")
        let beforeConcurrentEdit = try placementStore.positions()
        var concurrentEdit = beforeConcurrentEdit
        concurrentEdit[keys[0]]! += 100
        try placementStore.save(concurrentEdit, replacing: beforeConcurrentEdit)
        finishScan.signal()
        await backgroundRefresh.value
        assert(backgroundModel.entries.isEmpty, "A scan must discard results captured before a concurrent layout change")
        let afterConcurrentEdit = try placementStore.positions()
        assert(afterConcurrentEdit == concurrentEdit)
        print("Modern model: left/right native writes, empty/nonempty cross-section moves, undo, stale targets and manual profile choice passed")
        print("Profiles/spacers: shown-state restoration, full/partial registration rollback, stale drops, native position restoration, width validation, copy, switch/delete undo, removal and stale visibility undo passed")
        print("Recapture: temporary visibility restores on success, failure, cancellation and interrupted-capture recovery")
        print("Insertion: migration, independent marker movement, before/after drops, profile copy/undo, new-app order/visibility, persistence and idempotent scans passed")
        print("Background discovery: nonblocking editor state and stale scan rejection passed")
        print("Incremental refresh: unchanged scans publish nothing; native order and approval changes remain observable")
        print("Image cache lifetime: departed images released, current images reused and disk images restored")
        print("Temporary reveal: Hidden only, unchanged Always Hidden, idempotence, authored layout preservation, restoration and edit cleanup passed")
        print("Spacer content: legacy decoding, text/symbol persistence, invalid symbol rejection, stable anchors and profile copy/undo passed")
        print("Native spacers: blank/text/symbol rendering, stable identity, cached images, fallback content, resizing and removal passed")
    }

    @MainActor private static func checkMixedOrdering(root: URL, suite: String) async throws {
        let defaults = UserDefaults(suiteName: suite + ".mixed")!
        defer { defaults.removePersistentDomain(forName: suite + ".mixed") }
        let keys = (1...3).map { "status:com.example.mixed\($0)::Item-0" }
        let unrelated = "module:Unrelated"
        let positionURL = root.appendingPathComponent("mixed-order.plist")
        let visibilityURL = root.appendingPathComponent("mixed-visibility.plist")
        let store = MenuBarPositionStore(url: positionURL, backupURL: root.appendingPathComponent("mixed-order.before.plist"))
        let visibility = MenuBarVisibilityStore(url: visibilityURL, backupURL: root.appendingPathComponent("mixed-visibility.before.plist"))
        let records = (1...3).map { ["location": ["bundle": ["_0": "com.example.mixed\($0)"]], "isAllowed": true] as [String: Any] }
        let tracked = try PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0)
        try PropertyListSerialization.data(fromPropertyList: ["trackedApplications": tracked], format: .binary, options: 0).write(to: visibilityURL)
        func makeModel(_ profile: MenuBarLayoutProfile, positions: [String: Double]) async throws -> ModernMenuBarLayoutModel {
            try PropertyListSerialization.data(fromPropertyList: ["TrailingItemPreferredPositions": positions], format: .binary, options: 0).write(to: positionURL)
            defaults.set(try JSONEncoder().encode([profile]), forKey: "MenuBarLayoutProfiles.v1")
            defaults.set(profile.id.uuidString, forKey: "MenuBarLayoutActiveProfile.v1")
            let model = ModernMenuBarLayoutModel(defaults: defaults, positionStore: store, visibilityStore: visibility,
                                                spacerManager: FixtureSpacers(positions: store)) { _, positions, _, _ in
                keys.enumerated().map { index, key in
                    ModernMenuBarEntry(id: key, name: key, bundleID: "com.example.mixed\(index + 1)", pid: -1,
                                      frame: .null, positionKey: key, identifier: "Item-0", nativeTitle: "", isVisible: false)
                }.sorted { positions[$0.id]! > positions[$1.id]! }
            }
            await model.refresh()
            return model
        }
        for count in 1...2 {
            var spacers = (0..<count).map { _ in MenuBarLayoutSpacer(section: .visible, beforeID: keys[1]) }
            if count == 2 { spacers[0].beforeID = "spacer:\(spacers[1].id.uuidString)" }
            let spacerIDs = spacers.map { "spacer:\($0.id.uuidString)" }
            let spacerKeys = spacers.map { MenuBarSpacerManager.positionKey(for: $0.id) }
            let ids = [keys[0]] + spacerIDs + Array(keys.dropFirst())
            let nativeKeys = [keys[0]] + spacerKeys + Array(keys.dropFirst())
            var initial = Dictionary(uniqueKeysWithValues: nativeKeys.enumerated().map { ($1, Double(600 - $0 * 100)) })
            initial[unrelated] = 725
            let profile = MenuBarLayoutProfile(name: "Mixed", positions: initial, spacers: spacers)
            for source in ids {
                for target in ids.map(Optional.some) + [nil] where source != target {
                    let model = try await makeModel(profile, positions: initial)
                    let originalProfiles = model.profiles
                    assert(model.displayEntries(in: .visible).map(\.id) == ids, "Spacer chains must retain their saved order")
                    var expected = ids.filter { $0 != source }
                    expected.insert(source, at: target.flatMap { expected.firstIndex(of: $0) } ?? expected.endIndex)
                    await model.drop(source, in: .visible, before: target)
                    let native = try store.positions()
                    let nativeIDs = zip(ids, nativeKeys).sorted { native[$0.1]! > native[$1.1]! }.map(\.0)
                    assert(model.errorMessage == nil)
                    assert(nativeIDs == expected, "Mixed native order differs for \(source) before \(target ?? "end")")
                    assert(model.displayEntries(in: .visible).map(\.id) == expected,
                           "Editor order must agree with the native icon/spacer order")
                    assert(native[unrelated] == initial[unrelated], "Mixed sorting must preserve unrelated native positions")
                    if model.canUndo { await model.undo() }
                    let restored = try store.positions()
                    assert(restored == initial)
                    assert(model.profiles == originalProfiles, "Undo must restore spacer anchors and placement metadata")
                    let approvals = try visibility.approvals()
                    assert(approvals.values.allSatisfy { $0 }, "Same-section sorting must preserve visibility")
                }
            }
            let model = try await makeModel(profile, positions: initial)
            let external = try MenuBarPositionStore.reordered(initial, keys: nativeKeys, moving: keys[2], before: spacerKeys[0])
            try store.save(external, replacing: initial)
            await model.refresh(captureImages: false)
            assert(model.displayEntries(in: .visible).map(\.id) == [keys[0], keys[2]] + spacerIDs + [keys[1]],
                   "Refresh must show externally authored native order instead of stale spacer anchors")

            var hiddenProfile = profile
            hiddenProfile.sections["com.example.mixed2"] = .hidden
            for index in hiddenProfile.spacers.indices { hiddenProfile.spacers[index].section = .hidden }
            let hiddenPositions = initial.filter { !spacerKeys.contains($0.key) }
            hiddenProfile.positions = hiddenPositions
            try visibility.setAllowed(false, for: "com.example.mixed2", replacing: true)
            let hiddenModel = try await makeModel(hiddenProfile, positions: hiddenPositions)
            let marker = ModernMenuBarEntry.insertionMarkerID
            assert(hiddenModel.displayEntries(in: .hidden).map(\.id) == spacerIDs + [keys[1], marker])
            let originalHiddenProfile = hiddenModel.profiles
            await hiddenModel.drop(keys[2], in: .hidden, before: spacerIDs.last)
            var expected = spacerIDs + [keys[1], marker]
            expected.insert(keys[2], at: count - 1)
            assert(hiddenModel.errorMessage == nil && hiddenModel.displayEntries(in: .hidden).map(\.id) == expected,
                   "Unregistered hidden spacer targets must retain their position around a cross-section drop")
            await hiddenModel.undo()
            assert(hiddenModel.profiles == originalHiddenProfile)
            await hiddenModel.drop(keys[1], in: .visible, before: nil)
            assert(hiddenModel.displayEntries(in: .hidden).map(\.id) == spacerIDs + [marker],
                   "Moving an anchor out of its section must preserve the remaining spacer chain")
            await hiddenModel.undo()
            assert(hiddenModel.profiles == originalHiddenProfile)
            try visibility.setAllowed(true, for: "com.example.mixed2", replacing: false)
        }
        print("Mixed ordering: every icon/spacer destination, chains, end insertion, external order, unregistered hidden targets, cross-section anchors, unrelated positions and undo passed")
    }
}
