import ApplicationServices
import Cocoa

struct ModernMenuBarEntry: Identifiable {
    static let insertionMarkerID = "new-item-insertion"
    var isInsertionMarker: Bool { id == Self.insertionMarkerID }

    let id: String
    let name: String
    let bundleID: String
    let pid: pid_t
    let frame: CGRect
    let positionKey: String?
    let identifier: String
    let nativeTitle: String
    let isVisible: Bool
    let spacer: MenuBarLayoutSpacer?
    var isSpacer: Bool { spacer != nil }

    init(id: String, name: String, bundleID: String, pid: pid_t, frame: CGRect, positionKey: String?, identifier: String,
         nativeTitle: String, isVisible: Bool, spacer: MenuBarLayoutSpacer? = nil) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.pid = pid
        self.frame = frame
        self.positionKey = positionKey
        self.identifier = identifier
        self.nativeTitle = nativeTitle
        self.isVisible = isVisible
        self.spacer = spacer
    }
}

enum ModernMenuBarDiscovery {
    struct Application: Sendable {
        let pid: pid_t
        let bundleID: String
        let name: String
    }

    private struct Observation {
        let element: AXUIElement
        var entry: ModernMenuBarEntry
    }

    /// MenuBarAgent does not expose individual items through WindowServer.
    static func isMenuBarItem(at point: CGPoint) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success else {
            return true
        }
        for _ in 0..<8 {
            guard let current = element else { return true }
            AXUIElementSetMessagingTimeout(current, 0.1)
            guard let role = value(current, kAXRoleAttribute) as? String else { return true }
            if [kAXMenuBarItemRole, kAXButtonRole, kAXPopUpButtonRole].contains(role) { return true }
            if role == kAXMenuBarRole || role == kAXApplicationRole { return false }
            guard let parent = value(current, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { return true }
            element = (parent as! AXUIElement)
        }
        return true
    }

    static func scan(_ applications: [Application], positions: [String: Double], menuBands: [CGRect], excluding excludedBundleID: String) -> [ModernMenuBarEntry] {
        var entries = applications.filter { $0.bundleID != excludedBundleID && $0.bundleID != "com.apple.MenuBarAgent" }
            .flatMap { observations($0, positions: positions, menuBands: menuBands).map(\.entry) }
        let counts = Dictionary(grouping: entries.compactMap(\.positionKey), by: { $0 }).mapValues(\.count)
        entries = entries.map { entry in
            guard let key = entry.positionKey, counts[key] != 1 else { return entry }
            return ModernMenuBarEntry(id: "\(entry.bundleID):\(entry.pid):\(entry.identifier):\(entry.nativeTitle)", name: entry.name,
                                      bundleID: entry.bundleID, pid: entry.pid, frame: entry.frame, positionKey: nil,
                                      identifier: entry.identifier, nativeTitle: entry.nativeTitle, isVisible: entry.isVisible)
        }
        return entries.sorted {
            switch ($0.positionKey.flatMap { positions[$0] }, $1.positionKey.flatMap { positions[$0] }) {
            case (let left?, let right?):
                if left != right { return left > right }
                if $0.frame.minX != $1.frame.minX { return $0.frame.minX < $1.frame.minX }
                return $0.id < $1.id
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return $0.id < $1.id
            }
        }
    }

    private static func observations(_ application: Application, positions: [String: Double], menuBands: [CGRect]) -> [Observation] {
        let app = AXUIElementCreateApplication(application.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let bar = value(app, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        let elements = items(bar as! AXUIElement)
        return elements.enumerated().compactMap { index, element in
            let identifier = value(element, kAXIdentifierAttribute) as? String ?? ""
            let title = value(element, kAXTitleAttribute) as? String ?? ""
            let key = MenuBarItemIdentityResolver.resolve(bundleID: application.bundleID, identifier: identifier, title: title,
                                                        itemCount: elements.count, positions: positions)
            let bounds = frame(element)
            guard key != nil || bounds.map({ rect in menuBands.contains { $0.contains(CGPoint(x: rect.midX, y: rect.midY)) } }) == true else { return nil }
            let visible = (value(element, "AXVisible") as? Bool ?? true)
                && (bounds.map { rect in menuBands.contains { $0.contains(CGPoint(x: rect.midX, y: rect.midY)) } } == true)
            let description = value(element, kAXDescriptionAttribute) as? String ?? ""
            let name = elements.count > 1 && !description.isEmpty && description != application.name
                ? "\(application.name) · \(description)" : application.name
            return Observation(element: element, entry: ModernMenuBarEntry(
                id: key ?? "\(application.bundleID):\(index)", name: name, bundleID: application.bundleID,
                pid: application.pid, frame: bounds ?? .null, positionKey: key,
                identifier: identifier, nativeTitle: title, isVisible: visible
            ))
        }
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func items(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 4 else { return [] }
        let role = value(element, kAXRoleAttribute) as? String
        let description = value(element, kAXRoleDescriptionAttribute) as? String
        if role == kAXMenuBarItemRole || description?.lowercased() == "status menu" { return [element] }
        var children = [AXUIElement]()
        for attribute in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, "AXContents"] {
            for child in value(element, attribute) as? [AXUIElement] ?? [] where !children.contains(where: { CFEqual($0, child) }) {
                children.append(child)
            }
        }
        return children.flatMap { items($0, depth: depth + 1) }
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin = value(element, kAXPositionAttribute), CFGetTypeID(origin) == AXValueGetTypeID(),
              let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(origin as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.width < 600, dimensions.height > 0, dimensions.height <= 80 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
