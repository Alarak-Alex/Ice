import Cocoa

/// Owns the native status items represented by the active configuration's spacers.
@MainActor
protocol MenuBarSpacerManaging: AnyObject {
    func synchronize(_ spacers: [MenuBarLayoutSpacer])
}

@MainActor
final class MenuBarSpacerManager: MenuBarSpacerManaging {
    private(set) var items = [UUID: NSStatusItem]()

    deinit {
        for item in items.values { NSStatusBar.system.removeStatusItem(item) }
    }

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
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "Spacer-\(spacer.id.uuidString)"
                items[spacer.id] = item
            }
            item.length = spacer.validatedWidth
            if let button = item.button {
                let name = "Spacer-\(spacer.id.uuidString)"
                let imageSize = NSSize(width: spacer.validatedWidth, height: 16)
                // Keep explicit blank content, matching the reference spacer setup.
                if button.image?.size != imageSize {
                    button.image = NSImage(size: imageSize)
                }
                button.title = ""
                button.imagePosition = .imageOnly
                button.identifier = NSUserInterfaceItemIdentifier(name)
                button.setAccessibilityIdentifier(name)
                button.setAccessibilityLabel(AppLanguage.localized("Spacer"))
                button.toolTip = AppLanguage.localized("Spacer")
            }
            item.isVisible = spacer.section == .visible
        }
    }
}
