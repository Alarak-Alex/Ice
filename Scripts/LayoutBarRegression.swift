// Compile with LayoutBarContainer.swift, AppLanguage.swift and MenuBarPositionStore.swift.
import Cocoa
import Combine
import SwiftUI

// Stand-ins isolate container layout from live menu bar items and macOS permissions.
struct MenuBarItem: Equatable {
    let windowID: Int
    let info: Int
    var revision = 0
}

final class MenuBarSection {
    enum Name: Hashable { case visible }
    let name = Name.visible
}

final class ItemManager: ObservableObject {
    struct Cache {
        var items: [MenuBarItem] = []
        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] { items }
    }
    @Published var itemCache = Cache()
}

final class NavigationState {
    var isLayoutDragging = false
}

final class AppState {
    let itemManager = ItemManager()
    let navigationState = NavigationState()
}

final class LayoutBarItemView: NSView {
    var item: MenuBarItem
    var isEnabled = true
    var hasContainer = false
    var oldContainerInfo: (container: LayoutBarContainer, index: Int)?

    init(appState: AppState, item: MenuBarItem) {
        self.item = item
        super.init(frame: CGRect(x: 0, y: 0, width: 24, height: 26))
    }

    required init?(coder: NSCoder) { fatalError("Unused") }
}

@main
struct LayoutBarRegression {
    @MainActor
    static func main() {
        let state = AppState()
        let container = LayoutBarContainer(appState: state, section: MenuBarSection(), spacing: 4)
        let first = MenuBarItem(windowID: 1, info: 7)
        let second = MenuBarItem(windowID: 2, info: 7)
        container.shouldAnimateNextLayoutPass = false
        container.setArrangedViews(items: [first, second])
        let views = container.arrangedViews
        assert(views.count == 2 && views[0] !== views[1], "Shared app info must not merge distinct windows")
        assert(views[1].frame.minX == views[0].frame.maxX + 4)

        var updated = first
        updated.revision = 1
        container.setArrangedViews(items: [updated, second])
        assert(container.arrangedViews[0] === views[0], "Metadata changes must reuse item views")
        assert(views[0].item.revision == 1)

        container.shouldAnimateNextLayoutPass = false
        container.setArrangedViews(items: [second, updated])
        assert(container.arrangedViews[0] === views[1], "Reordering must preserve view identity")
        assert(container.arrangedView(nearestTo: 0) === views[1])
        state.navigationState.isLayoutDragging = true
        container.setArrangedViews(items: [])
        assert(container.arrangedViews.count == 2, "Refresh must not replace a live drag")
        state.navigationState.isLayoutDragging = false
        container.setArrangedViews(items: [])
        assert(container.arrangedViews.isEmpty && views.allSatisfy { $0.superview == nil && !$0.hasContainer })

        let savedLanguage = UserDefaults.standard.object(forKey: "IceLanguage")
        defer { UserDefaults.standard.set(savedLanguage, forKey: "IceLanguage") }
        UserDefaults.standard.set("zh-Hans", forKey: "IceLanguage")
        assert(AppLanguage.current == .simplifiedChinese)
        assert(AppLanguage.current.locale.language.languageCode?.identifier == "zh")
        UserDefaults.standard.set("en", forKey: "IceLanguage")
        assert(AppLanguage.current == .english)
        UserDefaults.standard.set("unsupported", forKey: "IceLanguage")
        assert(AppLanguage.current == .system)

        var assignedProfile = MenuBarLayoutProfile(name: "Assigned", automaticDisplayID: 42)
        assignedProfile.spacers = [MenuBarLayoutSpacer(section: .hidden, beforeID: "status:one::Item-0")]
        let profileData = try! JSONEncoder().encode(assignedProfile)
        let decodedProfile = try! JSONDecoder().decode(MenuBarLayoutProfile.self, from: profileData)
        assert(decodedProfile.automaticDisplayID == 42, "Display assignment must persist")
        assert(decodedProfile.spacers.count == 1 && decodedProfile.spacers[0].section == .hidden,
               "Palette spacers must persist")
        var legacyProfile = try! JSONSerialization.jsonObject(with: profileData) as! [String: Any]
        legacyProfile.removeValue(forKey: "automaticDisplayID")
        let legacyData = try! JSONSerialization.data(withJSONObject: legacyProfile)
        assert((try? JSONDecoder().decode(MenuBarLayoutProfile.self, from: legacyData).automaticDisplayID) == nil,
               "Legacy profiles must decode without a display assignment")

        let visibilityRecords: [[String: Any]] = [
            ["location": ["bundle": ["_0": "com.example.one"]], "isAllowed": true],
            ["location": ["bundle": ["_0": "com.example.two"]], "isAllowed": false],
            ["system": true]
        ]
        let visibilityData = try! PropertyListSerialization.data(fromPropertyList: visibilityRecords, format: .binary, options: 0)
        assert((try! MenuBarVisibilityStore.approvals(in: visibilityData))["com.example.one"] == true)
        let hiddenVisibilityData = try! MenuBarVisibilityStore.replacing(in: visibilityData, bundleID: "com.example.one", allowed: false)
        assert((try! MenuBarVisibilityStore.approvals(in: hiddenVisibilityData))["com.example.one"] == false)

        let identities = [
            "status:com.example.app::Item-0": 300.0,
            "module:Clock": 200.0,
            "module:BentoBox-0": 100.0,
        ]
        assert(MenuBarItemIdentityResolver.resolve(bundleID: "com.example.app", identifier: "Item-0", title: "", itemCount: 1, positions: identities) == "status:com.example.app::Item-0")
        assert(MenuBarItemIdentityResolver.resolve(bundleID: "com.example.app", identifier: "", title: "", itemCount: 1, positions: identities) == "status:com.example.app::Item-0", "System modules must not disable a unique application match")
        assert(MenuBarItemIdentityResolver.resolve(bundleID: "com.example.app", identifier: "Clock", title: "", itemCount: 1, positions: identities) == "status:com.example.app::Item-0", "Application items must not claim a system module")
        assert(MenuBarItemIdentityResolver.resolve(bundleID: "com.example.other", identifier: "Clock", title: "", itemCount: 1, positions: identities) == nil)
        assert(MenuBarItemIdentityResolver.resolve(bundleID: "com.apple.systemuiserver", identifier: "Clock", title: "", itemCount: 1, positions: identities) == "module:Clock")
        assert(MenuBarItemIdentityResolver.resolve(bundleID: "com.apple.controlcenter", identifier: "BentoBox", title: "", itemCount: 1, positions: identities) == "module:BentoBox-0")

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let positions: [String: Double] = ["status:one::Item-0": 30.5, "status:two::Item-0": 20.5,
                                                "status:three::Item-0": 10.5, "module:Clock": 20.5, "status:stopped::Item-0": 90.5]
            let keys = ["status:one::Item-0", "module:Clock", "status:two::Item-0", "status:three::Item-0"]
            let reordered = try MenuBarPositionStore.reordered(positions, keys: keys, moving: keys[1], before: keys[0])
            assert(reordered["module:Clock"]! > reordered[keys[0]]! && reordered[keys[0]]! > reordered[keys[2]]!)
            assert(Set(keys.compactMap { reordered[$0] }).count == keys.count, "Tied native slots must be resolved deterministically")
            assert(reordered["status:stopped::Item-0"] == 90.5)
            let url = temporary.appendingPathComponent("menu.plist")
            let original = try PropertyListSerialization.data(fromPropertyList: ["TrailingItemPreferredPositions": positions,
                                                                                "unrelated": ["preserved": true]], format: .binary, options: 0)
            try original.write(to: url)
            let store = MenuBarPositionStore(url: url, backupURL: temporary.appendingPathComponent("backups/before.plist"))
            try store.save(reordered, replacing: positions)
            let saved = try store.positions()
            assert(saved == reordered)
            let written = try Data(contentsOf: url)
            let root = try PropertyListSerialization.propertyList(from: written, format: nil) as! [String: Any]
            assert((root["unrelated"] as? [String: Bool])?["preserved"] == true)
            let backup = try Data(contentsOf: store.backupURL)
            assert(backup == original)
            do {
                try store.save(positions, replacing: positions)
                assertionFailure("Stale updates must be refused")
            } catch MenuBarPositionStore.Failure.changed { }
            let afterRejectedWrite = try Data(contentsOf: url)
            assert(afterRejectedWrite == written)
            try store.save(positions, replacing: reordered)
            let restored = try store.positions()
            assert(restored == positions)
        } catch { fatalError("Menu bar preference regression: \(error)") }
        print("Layout identity, refresh during drag, removal and language persistence checks passed")
        print("Native menu bar order, backup, unrelated preferences, stale-write rejection and undo checks passed")
    }
}
