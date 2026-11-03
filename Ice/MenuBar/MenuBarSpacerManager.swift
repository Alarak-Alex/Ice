import Cocoa

/// Owns the native status items represented by the active configuration's spacers.
@MainActor
protocol MenuBarSpacerManaging: AnyObject {
    func synchronize(_ spacers: [MenuBarLayoutSpacer])
}

@MainActor
final class MenuBarSpacerManager: MenuBarSpacerManaging {
    private var items = [UUID: NSStatusItem]()

    static func positionKey(for id: UUID) -> String {
        "status:\(Constants.bundleIdentifier)::Spacer-\(id.uuidString)"
    }

    func synchronize(_ spacers: [MenuBarLayoutSpacer]) {
        let wanted = Set(spacers.map(\.id))
        for id in Array(items.keys) where !wanted.contains(id) {
            if let item = items.removeValue(forKey: id) { NSStatusBar.system.removeStatusItem(item) }
        }
        for spacer in spacers {
            let item: NSStatusItem
            if let existing = items[spacer.id] {
                item = existing
            } else {
                item = NSStatusBar.system.statusItem(withLength: spacer.validatedWidth)
                item.autosaveName = "Spacer-\(spacer.id.uuidString)"
                item.button?.image = nil
                item.button?.title = ""
                item.button?.setAccessibilityLabel(AppLanguage.localized("Spacer"))
                items[spacer.id] = item
            }
            item.length = spacer.validatedWidth
            item.isVisible = spacer.section == .visible
        }
    }
}
