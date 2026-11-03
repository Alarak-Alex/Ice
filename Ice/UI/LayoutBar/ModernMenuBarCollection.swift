import Cocoa
import SwiftUI
import OSLog

private let layoutDragLogger = os.Logger(subsystem: "com.jordanbaird.Ice", category: "LayoutDrag")

enum MenuBarLayoutDragPolicy {
    static func canBegin(eventType: NSEvent.EventType, appIsActive: Bool, windowIsKey: Bool,
                         pressedMouseButtons: Int, sessionIsActive: Bool) -> Bool {
        eventType == .leftMouseDragged && appIsActive && windowIsKey &&
            pressedMouseButtons & 1 != 0 && !sessionIsActive
    }
}

struct ModernMenuBarCollection: NSViewRepresentable {
    let entries: [ModernMenuBarEntry]
    let images: [String: NSImage]
    let showAppIcons: Bool
    let isEditable: Bool
    let emptyPlaceholder: String?
    let onDrop: (String, Int) -> Void
    let onSpacerChanged: (String, MenuBarLayoutSpacer) -> Void
    let onRemoveSpacer: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = MenuBarLayoutScrollView()
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.horizontalLineScroll = 40
        scroll.drawsBackground = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .allowed
        scroll.documentView = MenuBarLayoutItemStrip()
        scroll.registerForDraggedTypes([MenuBarLayoutItemStrip.pasteboardType, MenuBarSpacerPaletteChip.pasteboardType])
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let strip = scroll.documentView as? MenuBarLayoutItemStrip else { return }
        strip.isEditable = isEditable
        strip.showAppIcons = showAppIcons
        strip.onDrop = onDrop
        strip.onSpacerChanged = onSpacerChanged
        strip.onRemoveSpacer = onRemoveSpacer
        strip.placeholder.stringValue = emptyPlaceholder ?? ""
        strip.update(entries: entries, images: images)
        scroll.needsLayout = true
    }
}

private final class MenuBarLayoutScrollView: NSScrollView {
    func scrollHorizontally(to offset: CGFloat) {
        let maximum = max(0, (documentView?.bounds.width ?? 0) - contentSize.width)
        contentView.scroll(to: NSPoint(x: min(maximum, max(0, offset)), y: 0))
        reflectScrolledClipView(contentView)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let documentView, documentView.bounds.width > contentSize.width else {
            super.scrollWheel(with: event)
            return
        }
        if event.scrollingDeltaX != 0 {
            let scale = event.hasPreciseScrollingDeltas ? 1 : horizontalLineScroll
            scrollHorizontally(to: contentView.bounds.minX - event.scrollingDeltaX * scale)
        } else if !event.hasPreciseScrollingDeltas {
            scrollHorizontally(to: contentView.bounds.minX - event.scrollingDeltaY * horizontalLineScroll)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func layout() {
        super.layout()
        guard let strip = documentView as? MenuBarLayoutItemStrip else { return }
        strip.setFrameSize(NSSize(width: max(contentSize.width, strip.requiredWidth), height: contentSize.height))
        strip.needsLayout = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        (documentView as? MenuBarLayoutItemStrip)?.draggingEntered(sender) ?? []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        (documentView as? MenuBarLayoutItemStrip)?.draggingUpdated(sender) ?? []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        (documentView as? MenuBarLayoutItemStrip)?.draggingExited(sender)
    }
    override func draggingEnded(_ sender: NSDraggingInfo) {
        (documentView as? MenuBarLayoutItemStrip)?.draggingEnded(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        (documentView as? MenuBarLayoutItemStrip)?.performDragOperation(sender) ?? false
    }
}

struct MenuBarSpacerPaletteView: NSViewRepresentable {
    func makeNSView(context: Context) -> MenuBarSpacerPaletteChip {
        MenuBarSpacerPaletteChip()
    }

    func updateNSView(_ nsView: MenuBarSpacerPaletteChip, context: Context) { }
}

final class MenuBarSpacerPaletteChip: NSView, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("com.jordanbaird.Ice.menuBarSpacer")
    private let iconImage: NSImage
    private let label = NSTextField(labelWithString: AppLanguage.localized("Drag to add a spacer"))
    private(set) var isDragging = false

    override init(frame frameRect: NSRect) {
        iconImage = NSImage(systemSymbolName: "arrow.left.and.right.square.fill", accessibilityDescription: nil) ?? NSImage()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.shadowColor = NSColor.systemBlue.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 5
        layer?.shadowOffset = NSSize(width: 0, height: -1)
        let icon = NSImageView(image: iconImage)
        icon.contentTintColor = .white
        icon.frame = NSRect(x: 10, y: 7, width: 12, height: 12)
        addSubview(icon)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.frame = NSRect(x: 28, y: 6, width: label.intrinsicContentSize.width, height: 16)
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(AppLanguage.localized("Drag to add a spacer"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: label.intrinsicContentSize.width + 38, height: 26) }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 13, cornerHeight: 13, transform: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 13, yRadius: 13)
        let highlight = NSColor.systemBlue.blended(withFraction: 0.18, of: .white) ?? .systemBlue
        NSGradient(starting: highlight, ending: .systemBlue)?.draw(in: shape, angle: -90)
        NSColor.white.withAlphaComponent(0.22).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: 12.75, yRadius: 12.75)
        border.lineWidth = 0.5
        border.stroke()
    }

    func draggingImage() -> NSImage {
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return iconImage }
        cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    override func mouseDragged(with event: NSEvent) {
        guard MenuBarLayoutDragPolicy.canBegin(eventType: event.type, appIsActive: NSApp.isActive,
                                              windowIsKey: window?.isKeyWindow == true,
                                              pressedMouseButtons: NSEvent.pressedMouseButtons,
                                              sessionIsActive: isDragging) else { return }
        isDragging = true
        let item = NSPasteboardItem()
        item.setString("palette-spacer", forType: Self.pasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: draggingImage())
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .copy : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        layoutDragLogger.info("Palette drag ended operation=\(operation.rawValue)")
    }
}

/// Explicit frames keep every item on one row, including at narrow window sizes.
final class MenuBarLayoutItemStrip: NSView {
    static let pasteboardType = NSPasteboard.PasteboardType("com.jordanbaird.Ice.modernMenuBarItem")
    var isEditable = false
    var showAppIcons = true
    var onDrop: ((String, Int) -> Void)?
    var onSpacerChanged: ((String, MenuBarLayoutSpacer) -> Void)?
    var onRemoveSpacer: ((String) -> Void)?
    let placeholder = NSTextField(labelWithString: "")
    private(set) var itemViews = [MenuBarLayoutItemView]()
    private var insertionIndex: Int? { didSet { needsDisplay = true } }
    private var selectedID: String?
    private var panStart: (mouseX: CGFloat, offset: CGFloat)?
    var requiredWidth: CGFloat { itemViews.reduce(28) { $0 + $1.preferredWidth } }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([Self.pasteboardType, MenuBarSpacerPaletteChip.pasteboardType])
        placeholder.textColor = NSColor.labelColor.withAlphaComponent(0.5)
        placeholder.font = .systemFont(ofSize: 11, weight: .medium)
        placeholder.alignment = .center
        addSubview(placeholder)
        setAccessibilityRole(.list)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let scroll = enclosingScrollView as? MenuBarLayoutScrollView else { return }
        panStart = (scroll.convert(event.locationInWindow, from: nil).x, scroll.contentView.bounds.minX)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panStart, let scroll = enclosingScrollView as? MenuBarLayoutScrollView else { return }
        let mouseX = scroll.convert(event.locationInWindow, from: nil).x
        scroll.scrollHorizontally(to: panStart.offset + panStart.mouseX - mouseX)
    }

    override func mouseUp(with event: NSEvent) {
        panStart = nil
    }

    func update(entries: [ModernMenuBarEntry], images: [String: NSImage]) {
        let previous = Dictionary(uniqueKeysWithValues: itemViews.map { ($0.entryID, $0) })
        let identifiers = Set(entries.map(\.id))
        for view in itemViews where !identifiers.contains(view.entryID) { view.removeFromSuperview() }
        itemViews = entries.map { entry in
            let item = previous[entry.id] ?? MenuBarLayoutItemView(entryID: entry.id)
            item.spacer = entry.spacer
            item.isInsertionMarker = entry.isInsertionMarker
            item.updateImages(itemImage: entry.isSpacer || entry.isInsertionMarker ? nil : images[entry.id],
                              appImage: entry.isSpacer || entry.isInsertionMarker ? nil : NSRunningApplication(processIdentifier: entry.pid)?.icon,
                              showAppIcon: showAppIcons && !entry.isSpacer && !entry.isInsertionMarker)
            item.isEditable = isEditable && (entry.isSpacer || entry.isInsertionMarker || entry.positionKey != nil)
            item.toolTip = entry.name
            item.setAccessibilityLabel(entry.name)
            item.onSelect = { [weak self] in self?.select(entry.id) }
            item.onSpacerChanged = { [weak self] spacer in self?.onSpacerChanged?(entry.id, spacer) }
            item.onRemove = { [weak self] in self?.onRemoveSpacer?(entry.id) }
            if item.superview !== self { addSubview(item) }
            return item
        }
        placeholder.isHidden = !itemViews.isEmpty || placeholder.stringValue.isEmpty
        select(selectedID)
        needsLayout = true
    }

    private func select(_ id: String?) {
        selectedID = id
        for view in itemViews { view.isSelected = view.entryID == id }
        setAccessibilitySelectedChildren(itemViews.filter(\.isSelected))
    }

    override func layout() {
        super.layout()
        let startX = max(14, bounds.width - requiredWidth + 14)
        var x = startX
        for view in itemViews {
            let width = view.preferredWidth
            let height: CGFloat = view.isInsertionMarker ? 38 : 40
            view.frame = NSRect(x: x, y: (bounds.height - height) / 2, width: width, height: height)
            x += width
        }
        placeholder.frame = NSRect(x: 14, y: (bounds.height - 18) / 2, width: max(0, bounds.width - 28), height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let index = insertionIndex else { return }
        let x = index < itemViews.count ? itemViews[index].frame.minX : (itemViews.last?.frame.maxX ?? bounds.maxX - 14)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: x - 1, y: 14, width: 2, height: max(0, bounds.height - 28)), xRadius: 1, yRadius: 1).fill()
    }

    private func updateDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        let itemSource = sender.draggingSource is MenuBarLayoutItemView
        let paletteSource = sender.draggingPasteboard.string(forType: MenuBarSpacerPaletteChip.pasteboardType) != nil
        guard isEditable, (itemSource || paletteSource),
              (sender.draggingPasteboard.string(forType: Self.pasteboardType) != nil || paletteSource) else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        insertionIndex = itemViews.firstIndex { point.x < $0.frame.midX } ?? itemViews.count
        if let event = NSApp.currentEvent { _ = autoscroll(with: event) }
        return paletteSource ? .copy : .move
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { insertionIndex = nil }
    override func draggingEnded(_ sender: NSDraggingInfo) { insertionIndex = nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { insertionIndex = nil }
        guard updateDrop(sender) != [], let index = insertionIndex,
              let source = sender.draggingPasteboard.string(forType: Self.pasteboardType)
                ?? sender.draggingPasteboard.string(forType: MenuBarSpacerPaletteChip.pasteboardType) else { return false }
        onDrop?(source, index)
        layoutDragLogger.info("Accepted drag source=\(source, privacy: .public) insertion=\(index)")
        return true
    }
}

final class MenuBarLayoutItemView: NSView, NSDraggingSource {
    let entryID: String
    let icon = NSImageView()
    let appIcon = NSImageView()
    let spacerLabel = NSTextField(labelWithString: "")
    let insertionLabel = NSTextField(wrappingLabelWithString: AppLanguage.localized("New Items\nhere"))
    var isEditable = false
    var spacer: MenuBarLayoutSpacer? {
        didSet { needsDisplay = true; needsLayout = true }
    }
    var isSpacer: Bool { spacer != nil }
    var isInsertionMarker = false {
        didSet {
            insertionLabel.isHidden = !isInsertionMarker
            needsDisplay = true
            needsLayout = true
        }
    }
    var onSelect: (() -> Void)?
    var onSpacerChanged: ((MenuBarLayoutSpacer) -> Void)?
    var onRemove: (() -> Void)?
    private var widthPopover: NSPopover?
    private var didDrag = false
    private(set) var isDragging = false
    private var hasItemImage = false
    var preferredWidth: CGFloat {
        if isInsertionMarker { return 88 }
        if let spacer { return max(16, spacer.validatedWidth) }
        return max(40, min(300, (hasItemImage ? icon.image?.size.width ?? 0 : 18) + (appIcon.isHidden ? 20 : 35)))
    }
    var isSelected = false {
        didSet {
            layer?.backgroundColor = isSelected && !isInsertionMarker ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor : nil
            setAccessibilitySelected(isSelected)
        }
    }

    init(entryID: String) {
        self.entryID = entryID
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        icon.imageScaling = .scaleProportionallyDown
        appIcon.imageScaling = .scaleProportionallyDown
        addSubview(icon)
        addSubview(appIcon)
        spacerLabel.font = .menuBarFont(ofSize: 13)
        spacerLabel.textColor = .white
        spacerLabel.alignment = .center
        spacerLabel.lineBreakMode = .byTruncatingTail
        spacerLabel.isHidden = true
        spacerLabel.setAccessibilityElement(false)
        addSubview(spacerLabel)
        insertionLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        insertionLabel.textColor = .white
        insertionLabel.alignment = .center
        insertionLabel.maximumNumberOfLines = 2
        insertionLabel.isHidden = true
        insertionLabel.setAccessibilityElement(false)
        addSubview(insertionLabel)
        icon.setAccessibilityElement(false)
        appIcon.setAccessibilityElement(false)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    func updateImages(itemImage: NSImage?, appImage: NSImage?, showAppIcon: Bool) {
        if let spacer {
            hasItemImage = false
            icon.image = spacer.content == .symbol
                ? NSImage(systemSymbolName: spacer.trimmedSymbolName, accessibilityDescription: nil) : nil
            icon.contentTintColor = .white
            self.appIcon.image = nil
            self.appIcon.isHidden = true
            spacerLabel.stringValue = spacer.content == .text ? spacer.trimmedText : ""
            spacerLabel.isHidden = spacerLabel.stringValue.isEmpty
            needsLayout = true
            return
        }
        hasItemImage = itemImage != nil
        icon.contentTintColor = nil
        icon.image = itemImage ?? appImage
        appIcon.image = appImage
        appIcon.isHidden = !showAppIcon || itemImage == nil || appImage == nil
        spacerLabel.isHidden = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        if isSpacer {
            let size = min(18, max(0, bounds.width - 4))
            icon.frame = NSRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
            appIcon.frame = .zero
            spacerLabel.frame = NSRect(x: 2, y: (bounds.height - 18) / 2, width: max(0, bounds.width - 4), height: 18)
        } else if isInsertionMarker {
            icon.frame = .zero
            appIcon.frame = .zero
            insertionLabel.frame = bounds.insetBy(dx: 6, dy: 3)
        } else {
            let size = hasItemImage ? icon.image?.size ?? NSSize(width: 18, height: 18) : NSSize(width: 18, height: 18)
            let scale = min(1, 22 / max(1, size.height), (bounds.width - (appIcon.isHidden ? 12 : 29)) / max(1, size.width))
            let width = size.width * scale, height = size.height * scale
            let groupWidth = width + (appIcon.isHidden ? 0 : 17)
            let x = (bounds.width - groupWidth) / 2
            appIcon.frame = NSRect(x: x, y: bounds.midY - 6, width: 12, height: 12)
            icon.frame = NSRect(x: x + (appIcon.isHidden ? 0 : 17), y: (bounds.height - height) / 2, width: width, height: height)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        if isInsertionMarker {
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 9, yRadius: 9)
            NSGradient(starting: NSColor.controlAccentColor.withAlphaComponent(0.17),
                       ending: NSColor.controlAccentColor.withAlphaComponent(0.25))?.draw(in: shape, angle: 90)
            NSColor.controlAccentColor.withAlphaComponent(0.65).setStroke()
            shape.lineWidth = 1
            shape.stroke()
            return
        }
        guard isSpacer, icon.image == nil, spacerLabel.stringValue.isEmpty else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        path.move(to: NSPoint(x: bounds.midX, y: 8))
        path.line(to: NSPoint(x: bounds.midX, y: bounds.maxY - 8))
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        didDrag = false
        onSelect?()
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        showSpacerEditor()
        return true
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        showSpacerEditor()
    }

    @objc private func showSpacerEditor() {
        guard let spacer, isEditable, window != nil else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarSpacerEditor(spacer: spacer) { [weak self] updated in
            self?.onSpacerChanged?(updated)
        }.environment(\.locale, AppLanguage.current.locale))
        widthPopover?.close()
        widthPopover = popover
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard isSpacer, isEditable else { return nil }
        let menu = NSMenu()
        let edit = NSMenuItem(title: AppLanguage.localized("Edit Spacer…"), action: #selector(showSpacerEditor), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        let remove = NSMenuItem(title: AppLanguage.localized("Remove Spacer"), action: #selector(removeSpacer), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        return menu
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil { widthPopover?.close(); widthPopover = nil }
        super.viewWillMove(toSuperview: newSuperview)
    }

    @objc private func removeSpacer() {
        widthPopover?.close()
        onRemove?()
    }
    override func mouseDragged(with event: NSEvent) {
        guard isEditable, MenuBarLayoutDragPolicy.canBegin(eventType: event.type, appIsActive: NSApp.isActive,
                                                         windowIsKey: window?.isKeyWindow == true,
                                                         pressedMouseButtons: NSEvent.pressedMouseButtons,
                                                         sessionIsActive: isDragging) else { return }
        isDragging = true
        layoutDragLogger.info("Begin item drag source=\(self.entryID, privacy: .public)")
        didDrag = true
        widthPopover?.close()
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(entryID, forType: MenuBarLayoutItemStrip.pasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboard)
        let preview: NSImage?
        if (isInsertionMarker || isSpacer), let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(bitmap)
            preview = image
        } else {
            preview = isSpacer ? NSImage(systemSymbolName: "arrow.left.and.right.square.fill", accessibilityDescription: nil) : icon.image
        }
        draggingItem.setDraggingFrame(bounds, contents: preview)
        beginDraggingSession(with: [draggingItem], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = false
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        layoutDragLogger.info("Item drag ended source=\(self.entryID, privacy: .public) operation=\(operation.rawValue)")
    }
}

struct MenuBarSpacerEditor: View {
    @State var spacer: MenuBarLayoutSpacer
    let onChange: (MenuBarLayoutSpacer) -> Void

    private var symbolImage: NSImage? {
        NSImage(systemSymbolName: spacer.trimmedSymbolName, accessibilityDescription: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Spacer…").font(.headline)
            Picker("Content", selection: $spacer.content) {
                ForEach(MenuBarLayoutSpacer.Content.allCases, id: \.self) { content in
                    Text(content.title).tag(content)
                }
            }
            .pickerStyle(.segmented)
            switch spacer.content {
            case .blank:
                Text("A plain, empty spacer.").foregroundStyle(.secondary)
            case .text:
                TextField("Text", text: $spacer.text).textFieldStyle(.roundedBorder)
            case .symbol:
                HStack {
                    TextField("SF Symbol Name", text: $spacer.symbolName).textFieldStyle(.roundedBorder)
                    if let symbolImage {
                        Image(nsImage: symbolImage).frame(width: 20, height: 20)
                    }
                }
                if symbolImage == nil {
                    Text("Enter a valid SF Symbol name.").foregroundStyle(.secondary)
                }
            }
            Text("Spacer Width").font(.subheadline.weight(.medium))
            HStack {
                Slider(value: $spacer.width, in: 1...200).accessibilityLabel("Spacer Width")
                TextField("Spacer Width", value: $spacer.width, format: .number.precision(.fractionLength(0)))
                    .frame(width: 48)
            }
        }
        .padding(14)
        .frame(width: 280)
        .onChange(of: spacer) { _, value in
            guard value.width.isFinite else { return }
            if value.width != Double(value.validatedWidth) {
                spacer.width = Double(value.validatedWidth)
                return
            }
            guard value.content != .symbol || symbolImage != nil else { return }
            onChange(value)
        }
    }
}
