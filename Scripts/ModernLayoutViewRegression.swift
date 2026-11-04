// Compile with ModernMenuBarCollection, SettingsPaneHeader, discovery, profile, identity resolver and AppLanguage.
import Cocoa
import SwiftUI

@main
struct ModernLayoutViewRegression {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let appImage = NSImage(size: NSSize(width: 24, height: 24))
        let statusImage = NSImage(size: NSSize(width: 18, height: 18))
        let item = MenuBarLayoutItemView(entryID: "one")
        item.frame = NSRect(x: 30, y: 10, width: 40, height: 40)
        item.updateImages(itemImage: nil, appImage: appImage, showAppIcon: false)
        assert(item.icon.image === appImage, "The fallback icon must survive disabling app badges")
        item.updateImages(itemImage: statusImage, appImage: appImage, showAppIcon: true)
        item.layoutSubtreeIfNeeded()
        assert(item.icon.image === statusImage && !item.appIcon.isHidden)
        assert(item.appIcon.frame.maxX < item.icon.frame.minX, "The badge belongs beside the status image")
        assert(item.hitTest(NSPoint(x: 50, y: 30)) === item, "Images must not intercept item drag events")
        let wideImage = NSImage(size: NSSize(width: 90, height: 18))
        item.updateImages(itemImage: wideImage, appImage: appImage, showAppIcon: false)
        item.setFrameSize(NSSize(width: item.preferredWidth, height: 40))
        item.layoutSubtreeIfNeeded()
        assert(item.icon.frame.width == 90 && item.icon.frame.height == 18,
               "Text and wide status items must keep their native proportions")
        assert(item.preferredWidth == 110)

        assert(MenuBarLayoutDragPolicy.canBegin(eventType: .leftMouseDragged, appIsActive: true, windowIsKey: true, pressedMouseButtons: 1, sessionIsActive: false))
        assert(!MenuBarLayoutDragPolicy.canBegin(eventType: .leftMouseDragged, appIsActive: false, windowIsKey: true, pressedMouseButtons: 1, sessionIsActive: false))
        assert(!MenuBarLayoutDragPolicy.canBegin(eventType: .leftMouseDragged, appIsActive: true, windowIsKey: false, pressedMouseButtons: 1, sessionIsActive: false))
        assert(!MenuBarLayoutDragPolicy.canBegin(eventType: .leftMouseDragged, appIsActive: true, windowIsKey: true, pressedMouseButtons: 0, sessionIsActive: false))
        assert(!MenuBarLayoutDragPolicy.canBegin(eventType: .leftMouseDragged, appIsActive: true, windowIsKey: true, pressedMouseButtons: 1, sessionIsActive: true))
        let backgroundEvent = NSEvent.mouseEvent(with: .leftMouseDragged, location: .zero, modifierFlags: [],
                                               timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                               clickCount: 1, pressure: 0)!
        item.isEditable = true
        item.mouseDragged(with: backgroundEvent)
        let palette = MenuBarSpacerPaletteChip()
        palette.mouseDragged(with: backgroundEvent)
        assert(!item.isDragging && !palette.isDragging, "Background automation must not start a global drag session")
        palette.setFrameSize(palette.intrinsicContentSize)
        palette.layoutSubtreeIfNeeded()
        let palettePreview = palette.draggingImage()
        assert(palettePreview.size == palette.bounds.size, "The palette preview must retain the complete label's dimensions")
        let paletteBitmap = palettePreview.representations.compactMap { $0 as? NSBitmapImageRep }.first!
        let labelStart = Int(28 * CGFloat(paletteBitmap.pixelsWide) / palette.bounds.width)
        let containsLabel = (labelStart..<paletteBitmap.pixelsWide).contains { x in
            (0..<paletteBitmap.pixelsHigh).contains { y in
                guard let color = paletteBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                return color.alphaComponent > 0.5 && min(color.redComponent, color.greenComponent, color.blueComponent) > 0.85
            }
        }
        assert(containsLabel, "The palette drag preview must include its text instead of stretching the glyph")

        let entries = (0..<30).map { index in
            ModernMenuBarEntry(id: "item-\(index)", name: "Item \(index)", bundleID: "com.example.\(index)",
                              pid: -1, frame: .zero, positionKey: "status:com.example.\(index)::Item-0",
                              identifier: "Item-0", nativeTitle: "", isVisible: true)
        }
        var iconLoads = 0
        weak var departedAppIcon: NSImage?
        let cachedStrip = MenuBarLayoutItemStrip(frame: NSRect(x: 0, y: 0, width: 300, height: 76))
        autoreleasepool {
            let cachedEntries = (0..<3).map { index in
                ModernMenuBarEntry(id: "cached-\(index)", name: "Cached \(index)", bundleID: "com.example.cached\(index / 2)",
                                  pid: pid_t(8000 + index / 2), frame: .zero, positionKey: "status:cached-\(index)",
                                  identifier: "", nativeTitle: "", isVisible: true)
            }
            cachedStrip.loadAppIcon = { _ in
                iconLoads += 1
                return NSImage(size: NSSize(width: 24, height: 24))
            }
            var images = Dictionary(uniqueKeysWithValues: cachedEntries.map { ($0.id, statusImage) })
            cachedStrip.showAppIcons = false
            assert(cachedStrip.update(entries: cachedEntries, images: images))
            assert(iconLoads == 0, "Captured glyphs without app badges must not fetch application icons")
            cachedStrip.layoutSubtreeIfNeeded()
            assert(!cachedStrip.update(entries: cachedEntries, images: images),
                   "Identical view updates must not request another layout")
            cachedStrip.showAppIcons = true
            assert(cachedStrip.update(entries: cachedEntries, images: images))
            assert(iconLoads == 2, "Items from one process must share one cached application icon")
            images[cachedEntries[0].id] = NSImage(size: NSSize(width: 60, height: 18))
            assert(cachedStrip.update(entries: cachedEntries, images: images))
            assert(iconLoads == 2 && cachedStrip.itemViews[0].icon.image === images[cachedEntries[0].id],
                   "A fresh status glyph must update without reloading application icons")
            cachedStrip.isEditable = true
            assert(cachedStrip.update(entries: cachedEntries, images: images) && cachedStrip.itemViews.allSatisfy(\.isEditable),
                   "Editability changes must bypass the unchanged-content fast path")
            departedAppIcon = cachedStrip.itemViews[2].appIcon.image
            cachedStrip.update(entries: Array(cachedEntries.prefix(2)), images: images)
            let replacement = ModernMenuBarEntry(id: cachedEntries[0].id, name: "Replacement", bundleID: "com.example.replacement",
                                                pid: cachedEntries[0].pid, frame: .zero, positionKey: "status:replacement",
                                                identifier: "", nativeTitle: "", isVisible: true)
            cachedStrip.update(entries: [replacement], images: [:])
            assert(iconLoads == 3, "A reused PID with a different bundle must not inherit another application's icon")
            cachedStrip.update(entries: [], images: [:])
            cachedStrip.loadAppIcon = { _ in nil }
            cachedStrip.update(entries: [replacement], images: [:])
            assert(cachedStrip.itemViews[0].icon.image == nil)
            cachedStrip.loadAppIcon = { _ in NSImage(size: NSSize(width: 24, height: 24)) }
            assert(cachedStrip.update(entries: [replacement], images: [:]) && cachedStrip.itemViews[0].icon.image != nil,
                   "An icon unavailable during launch must be retried rather than cached as missing forever")
        }
        assert(departedAppIcon == nil, "Departed processes must leave the app-icon cache and native views")
        assert(cachedStrip.itemViews[0].icon.image != nil, "Eviction must preserve the remaining application's fallback icon")

        let host = NSHostingView(rootView: ModernMenuBarCollection(
            entries: entries, images: [:], showAppIcons: false, isEditable: true, emptyPlaceholder: nil,
            onDrop: { _, _ in assertionFailure("Browsing must not reorder menu bar items") },
            onSpacerChanged: { _, _ in }, onRemoveSpacer: { _ in }
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 76),
                              styleMask: [], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: .now.addingTimeInterval(0.1))
        func findScrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.documentView is MenuBarLayoutItemStrip { return scroll }
            return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
        }
        let scroll = findScrollView(in: host)!
        scroll.layoutSubtreeIfNeeded()
        let scrollingStrip = scroll.documentView as! MenuBarLayoutItemStrip
        let maximumOffset = scrollingStrip.bounds.width - scroll.contentSize.width
        assert(maximumOffset > 0, "Overflowing items need a horizontally scrollable document")
        func backgroundMouse(_ type: NSEvent.EventType, x: CGFloat) -> NSEvent {
            let location = scroll.convert(NSPoint(x: x, y: 4), to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                      timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                      eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        scrollingStrip.mouseDown(with: backgroundMouse(.leftMouseDown, x: 250))
        scrollingStrip.mouseDragged(with: backgroundMouse(.leftMouseDragged, x: 100))
        assert(scroll.contentView.bounds.minX == 150, "Dragging empty bar space left must reveal items on the right")
        scrollingStrip.mouseUp(with: backgroundMouse(.leftMouseUp, x: 100))
        assert(!scrollingStrip.itemViews.contains(where: \.isDragging), "Panning must not start an item drag session")
        assert(scroll.hasHorizontalScroller, "Overflow must expose a native horizontal scroller")
        assert(Set(scrollingStrip.itemViews.map { $0.frame.midY }).count == 1
               && scroll.contentView.bounds.height >= 40,
               "Both system scroller styles must retain one complete row of icons")
        func wheel(_ x: Int32, _ y: Int32, units: CGScrollEventUnit) -> NSEvent {
            NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: units,
                                    wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)!)!
        }
        scroll.scrollWheel(with: wheel(0, -3, units: .line))
        assert(scroll.contentView.bounds.minX > 150, "A mouse wheel must browse an overflowing horizontal strip")
        let afterWheel = scroll.contentView.bounds.minX
        scroll.scrollWheel(with: wheel(-80, 0, units: .pixel))
        assert(scroll.contentView.bounds.minX > afterWheel, "Trackpad horizontal deltas must remain native")
        scrollingStrip.mouseDown(with: backgroundMouse(.leftMouseDown, x: 250))
        scrollingStrip.mouseDragged(with: backgroundMouse(.leftMouseDragged, x: -5000))
        scrollingStrip.mouseUp(with: backgroundMouse(.leftMouseUp, x: -5000))
        assert(scroll.contentView.bounds.minX == maximumOffset)
        assert(scroll.documentVisibleRect.contains(scrollingStrip.itemViews.last!.frame),
               "The final item must be reachable rather than permanently clipped")
        scrollingStrip.update(entries: entries, images: [:])
        scroll.layoutSubtreeIfNeeded()
        assert(scroll.contentView.bounds.minX == maximumOffset, "A refresh must preserve the browsing position")
        assert(scrollingStrip.itemViews.last!.accessibilityPerformPress() && scrollingStrip.itemViews.last!.isSelected)
        scrollingStrip.mouseDown(with: backgroundMouse(.leftMouseDown, x: 100))
        scrollingStrip.mouseDragged(with: backgroundMouse(.leftMouseDragged, x: 5000))
        scrollingStrip.mouseUp(with: backgroundMouse(.leftMouseUp, x: 5000))
        assert(scroll.contentView.bounds.minX == 0, "Dragging right must return to the first item without overshooting")
        scrollingStrip.mouseDragged(with: backgroundMouse(.leftMouseDragged, x: -100))
        assert(scroll.contentView.bounds.minX == 0, "A stray drag after mouse-up must not keep panning")

        let strip = MenuBarLayoutItemStrip(frame: NSRect(x: 0, y: 0, width: 300, height: 72))
        strip.isEditable = true
        strip.update(entries: entries, images: [:])
        strip.layoutSubtreeIfNeeded()
        assert(Set(strip.itemViews.map { $0.frame.midY }).count == 1, "A narrow viewport must never make a second row")
        assert(strip.itemViews.last!.frame.maxX > strip.bounds.maxX)
        assert(strip.itemViews[0].accessibilityPerformPress())
        assert(strip.itemViews[0].isSelected && strip.itemViews[0].isAccessibilitySelected(),
               "Accessibility press must select the layout item")
        assert(strip.itemViews[1].accessibilityPerformPress())
        assert(!strip.itemViews[0].isSelected && strip.itemViews[1].isSelected)
        assert(strip.accessibilitySelectedChildren()?.count == 1, "The strip must expose one selected item")
        let oldViews = strip.itemViews
        strip.update(entries: entries.reversed(), images: [:])
        strip.layoutSubtreeIfNeeded()
        assert(strip.itemViews.first === oldViews.last, "Reordering must reuse native item views")
        let marker = ModernMenuBarEntry(id: ModernMenuBarEntry.insertionMarkerID, name: "New Items\nhere",
                                       bundleID: "com.example.editor", pid: -1, frame: .zero, positionKey: nil,
                                       identifier: "", nativeTitle: "", isVisible: false)
        strip.update(entries: [entries[0], marker, entries[1]], images: [:])
        strip.layoutSubtreeIfNeeded()
        let markerView = strip.itemViews[1]
        assert(markerView.isInsertionMarker && markerView.isEditable && markerView.preferredWidth == 88)
        assert(markerView.frame.height == 38)
        assert(!markerView.insertionLabel.isHidden && markerView.icon.frame == .zero && markerView.appIcon.frame == .zero)
        for text in ["New Items\nhere", "新项目\n在此处"] {
            let label = markerView.insertionLabel
            label.stringValue = text
            let bitmap = label.bitmapImageRepForCachingDisplay(in: label.bounds)!
            label.cacheDisplay(in: label.bounds, to: bitmap)
            let textRows = (0..<bitmap.pixelsHigh).filter { y in
                (0..<bitmap.pixelsWide).contains { x in
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                    return color.alphaComponent > 0.25 && min(color.redComponent, color.greenComponent, color.blueComponent) > 0.75
                }
            }
            assert((textRows.last ?? 0) - (textRows.first ?? 0) >= 16,
                   "Both insertion-label lines must be rendered without clipping in \(text)")
        }
        assert(markerView.hitTest(markerView.frame.origin) === markerView, "The label must not intercept marker dragging")
        assert(Set(strip.itemViews.map { $0.frame.midY }).count == 1)
        assert(markerView.accessibilityPerformPress() && markerView.isAccessibilitySelected())
        assert(markerView.menu(for: backgroundEvent) == nil, "The marker must not expose spacer deletion or width controls")
        assert(strip.itemViews.filter(\.isInsertionMarker).count == 1)
        var spacer = MenuBarLayoutSpacer(section: .visible, width: 64, content: .text, text: "  Focus  ")
        func updateSpacerView() -> MenuBarLayoutItemView {
            let entry = ModernMenuBarEntry(id: "spacer:\(spacer.id)", name: "Spacer", bundleID: "com.example.editor",
                                          pid: -1, frame: .zero, positionKey: nil, identifier: "", nativeTitle: "",
                                          isVisible: true, spacer: spacer)
            strip.update(entries: [entry], images: [:])
            strip.layoutSubtreeIfNeeded()
            return strip.itemViews[0]
        }
        let spacerView = updateSpacerView()
        assert(spacerView.spacerLabel.stringValue == "Focus" && !spacerView.spacerLabel.isHidden)
        assert(spacerView.icon.image == nil && spacerView.appIcon.isHidden)
        assert(spacerView.preferredWidth == 64)
        let menu = spacerView.menu(for: backgroundEvent)!
        assert(menu.items.count == 2 && menu.items.allSatisfy { $0.target === spacerView },
               "A spacer must expose edit and remove actions without an application menu")
        spacer.content = .symbol
        spacer.symbolName = "star.fill"
        assert(updateSpacerView() === spacerView && spacerView.icon.image != nil && spacerView.spacerLabel.isHidden)
        spacer.content = .blank
        assert(updateSpacerView() === spacerView && spacerView.icon.image == nil && spacerView.spacerLabel.isHidden)
        if let directory = ProcessInfo.processInfo.environment["ICE_SPACER_EDITOR_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory)
            try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for content in MenuBarLayoutSpacer.Content.allCases {
                spacer.content = content
                let editor = NSHostingView(rootView: MenuBarSpacerEditor(spacer: spacer) { _ in }
                    .background(Color(nsColor: .windowBackgroundColor)))
                editor.appearance = NSAppearance(named: .aqua)
                let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 240),
                                     styleMask: [], backing: .buffered, defer: false)
                panel.contentView = editor
                editor.layoutSubtreeIfNeeded()
                let size = editor.fittingSize
                assert(size.width == 280 && size.height > 120)
                panel.setContentSize(size)
                editor.layoutSubtreeIfNeeded()
                let bitmap = editor.bitmapImageRepForCachingDisplay(in: editor.bounds)!
                editor.cacheDisplay(in: editor.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!
                    .write(to: url.appendingPathComponent("\(content.rawValue).png"))
            }
        }
        if let directory = ProcessInfo.processInfo.environment["ICE_LAYOUT_APPEARANCE_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory)
            try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for (language, title, subtitle) in [
                ("en", "Menu Bar", "Drag items between sections to rearrange the menu bar."),
                ("zh", "菜单栏", "在各部分之间拖动项目以重新排列菜单栏。")
            ] {
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    let content = VStack(spacing: 24) {
                        SettingsPaneHeader(title: LocalizedStringKey(title), subtitle: LocalizedStringKey(subtitle),
                                           systemImage: "rectangle.bottomthird.inset.filled")
                            .controlSize(.large)
                            .frame(minHeight: 181)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
                        MenuBarSpacerPaletteView().fixedSize().padding(24)
                    }
                    .padding(16)
                    .frame(width: 650)
                    .background(Color(nsColor: .windowBackgroundColor))
                    let host = NSHostingView(rootView: content)
                    host.appearance = NSAppearance(named: appearance)
                    let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 300),
                                         styleMask: [], backing: .buffered, defer: false)
                    panel.contentView = host
                    host.layoutSubtreeIfNeeded()
                    panel.setContentSize(host.fittingSize)
                    host.layoutSubtreeIfNeeded()
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try! bitmap.representation(using: .png, properties: [:])!
                        .write(to: url.appendingPathComponent("\(language)-\(appearance.rawValue).png"))
                }
            }
        }
        print("Modern layout: fallback icons, app badges, hit testing, selection accessibility, single row, stable views and background drag rejection passed")
        print("Horizontal browsing: empty-space panning, mouse wheel, trackpad, both edges, last-item selection and refresh offset passed")
        print("Insertion marker: one row, fixed geometry, bilingual two-line rendering, label hit testing, selection and distinct spacer behavior passed")
        print("Spacer views: trimmed text, template symbols, blank content, stable native views and edit/remove actions passed")
        print("Palette: complete label dimensions and visible text retained in the native drag preview")
        print("Incremental views: unchanged layout skipped, app icons fetched only when displayed and shared per process, fresh glyphs and editing state preserved, departed icons released")
    }
}
