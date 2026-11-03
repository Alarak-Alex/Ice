// Compile with the modern model, discovery, identity, profile, language and preference stores.
import Cocoa

enum Constants { static let bundleIdentifier = "com.jordanbaird.Ice.Regression" }
extension NSScreen {
    var displayID: CGDirectDisplayID { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID }
}
@MainActor final class AppState { }

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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ice-model-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "com.jordanbaird.Ice.Regression.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
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
        model.updateSpacerWidth(sourceID, to: 900)
        assert(spacers.widths[spacer.id] == 200)
        model.updateSpacerWidth(sourceID, to: 48)
        assert(spacers.widths[spacer.id] == 48)
        model.updateSpacerWidth(sourceID, to: .nan)
        assert(spacers.widths[spacer.id] == 48, "Invalid widths must not reach the native host")
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
        model.updateSpacerWidth(retainedID, to: 48)
        let originalProfile = model.activeProfileID!
        model.createProfile(named: "Copied spacer")
        let copiedProfile = model.activeProfileID!
        assert(model.activeProfile!.spacers.first!.id == retained.id, "Copied configurations must retain their spacers")
        model.updateSpacerWidth(retainedID, to: 32)
        await model.selectProfile(originalProfile)
        assert(spacers.widths[retained.id] == 48)
        await model.undo()
        assert(model.activeProfileID == copiedProfile && spacers.widths[retained.id] == 32)
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
    }
}
