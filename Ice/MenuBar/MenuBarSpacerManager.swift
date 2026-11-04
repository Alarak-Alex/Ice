import Cocoa

/// Owns the native status items represented by the active configuration's spacers.
@MainActor
protocol MenuBarSpacerManaging: AnyObject {
    var visiblePositionKeys: Set<String> { get }
    func synchronize(_ spacers: [MenuBarLayoutSpacer])
}

@MainActor
final class MenuBarSpacerManager: MenuBarSpacerManaging {
    private(set) var items = [UUID: NSStatusItem]()
    private var renderedSpacers = [UUID: MenuBarLayoutSpacer]()

    deinit {
        for item in items.values { NSStatusBar.system.removeStatusItem(item) }
    }

    static func positionKey(for id: UUID) -> String {
        "status:\(Constants.bundleIdentifier)::Spacer-\(id.uuidString)"
    }

    var visiblePositionKeys: Set<String> {
        Set(items.compactMap { id, item in
            guard item.isVisible, item.button != nil,
                  item.autosaveName == "Spacer-\(id.uuidString)" else { return nil }
            return Self.positionKey(for: id)
        })
    }

    func synchronize(_ spacers: [MenuBarLayoutSpacer]) {
        let wanted = Set(spacers.map(\.id))
        for id in Array(items.keys) where !wanted.contains(id) {
            if let item = items.removeValue(forKey: id) { NSStatusBar.system.removeStatusItem(item) }
            renderedSpacers.removeValue(forKey: id)
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
            if item.length != spacer.validatedWidth { item.length = spacer.validatedWidth }
            if let button = item.button {
                let name = "Spacer-\(spacer.id.uuidString)"
                let previous = renderedSpacers[spacer.id]
                if previous?.validatedWidth != spacer.validatedWidth || previous?.content != spacer.content ||
                    previous?.trimmedText != spacer.trimmedText || previous?.trimmedSymbolName != spacer.trimmedSymbolName {
                    button.title = ""
                    button.image = nil
                    button.imagePosition = .imageOnly
                    switch spacer.content {
                    case .text where !spacer.trimmedText.isEmpty:
                        button.title = spacer.trimmedText
                        button.imagePosition = .noImage
                    case .symbol:
                        button.image = NSImage(systemSymbolName: spacer.trimmedSymbolName, accessibilityDescription: nil)
                            ?? NSImage(size: NSSize(width: spacer.validatedWidth, height: 16))
                    case .blank, .text:
                        // Empty content still needs an image for MenuBarAgent registration.
                        button.image = NSImage(size: NSSize(width: spacer.validatedWidth, height: 16))
                    }
                }
                renderedSpacers[spacer.id] = spacer
                button.identifier = NSUserInterfaceItemIdentifier(name)
                button.setAccessibilityIdentifier(name)
                button.setAccessibilityLabel(spacer.content == .text && !spacer.trimmedText.isEmpty
                    ? spacer.trimmedText : AppLanguage.localized("Spacer"))
                button.toolTip = AppLanguage.localized("Spacer")
            }
            item.isVisible = spacer.section == .visible
        }
    }
}
