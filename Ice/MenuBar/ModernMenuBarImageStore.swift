import Cocoa
import OSLog
import ScreenCaptureKit

/// Captures MenuBarAgent's visible glyphs and retains them while their apps are hidden.
@MainActor
final class ModernMenuBarImageStore {
    private struct SavedImage: Codable {
        let scale: CGFloat
    }

    private struct Strip {
        let image: CGImage
        let frame: CGRect
        let scale: CGFloat
    }

    enum Failure: LocalizedError {
        case permission, noImages, incomplete
        var errorDescription: String? {
            switch self {
            case .permission: AppLanguage.localized("Allow Screen Recording in System Settings to capture menu bar item images.")
            case .noImages: AppLanguage.localized("No menu bar item images could be captured. Show the menu bar and try again.")
            case .incomplete: AppLanguage.localized("Some hidden item images could not be captured. Make room in the menu bar and try again.")
            }
        }
    }

    private let directory: URL
    private var index = [String: SavedImage]()
    private var loaded = [String: NSImage]()
    private let logger = os.Logger(subsystem: "com.jordanbaird.Ice", category: "MenuBarImages")

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Ice/MenuBarItemImages.v5")) {
        self.directory = directory
        if let data = try? Data(contentsOf: directory.appendingPathComponent("index.json")),
           let saved = try? JSONDecoder().decode([String: SavedImage].self, from: data) { index = saved }
    }

    func images(for entries: [ModernMenuBarEntry]) -> [String: NSImage] {
        var result = [String: NSImage]()
        for entry in entries {
            if let image = loaded[entry.id] { result[entry.id] = image; continue }
            guard let metadata = index[entry.id], metadata.scale.isFinite, metadata.scale > 0,
                  let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(ModernMenuBarItemImages.fileName(for: entry.id)) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let value = NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / metadata.scale, height: CGFloat(image.height) / metadata.scale))
            loaded[entry.id] = value
            result[entry.id] = value
        }
        return result
    }

    @discardableResult
    func capture(_ entries: [ModernMenuBarEntry], rescan: () async -> [ModernMenuBarEntry]) async throws -> Set<String> {
        guard CGPreflightScreenCaptureAccess() else { throw Failure.permission }
        try Task.checkCancellation()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
        var strips = [Strip]()
        for screen in NSScreen.screens {
            let bounds = CGDisplayBounds(screen.displayID)
            let height = max(22, screen.frame.maxY - screen.visibleFrame.maxY)
            let frame = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: min(64, height))
            guard entries.contains(where: { $0.isVisible && frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }),
                  let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(origin: .zero, size: frame.size)
            configuration.width = Int(frame.width * scale)
            configuration.height = Int(frame.height * scale)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            strips.append(Strip(image: image, frame: frame, scale: scale))
        }
        let after = await rescan()
        try Task.checkCancellation()
        let stable = entries.filter { entry in
            entry.isVisible && after.contains { $0.id == entry.id && $0.isVisible && ModernMenuBarItemImages.settled(entry.frame, $0.frame) }
        }
        let captured = await Self.process(strips, entries: stable)
        try Task.checkCancellation()
        for (id, value) in captured {
            loaded[id] = NSImage(cgImage: value.image, size: CGSize(width: CGFloat(value.image.width) / value.scale,
                                                                 height: CGFloat(value.image.height) / value.scale))
            index[id] = SavedImage(scale: value.scale)
        }
        if !captured.isEmpty {
            do { try await Self.save(captured, index: JSONEncoder().encode(index), directory: directory) }
            catch { logger.error("Could not save menu bar images: \(error)") }
        }
        logger.info("Captured \(captured.count) menu bar item images")
        return Set(captured.keys)
    }

    private struct CapturedImage {
        let image: CGImage
        let scale: CGFloat
    }

    @concurrent
    private static func process(_ strips: [Strip], entries: [ModernMenuBarEntry]) async -> [String: CapturedImage] {
        var result = [String: CapturedImage]()
        for strip in strips {
            var crops = [String: CGImage]()
            var light = 0, dark = 0
            for entry in entries {
                guard let rect = ModernMenuBarItemImages.cropRect(item: entry.frame, strip: strip.frame, scale: strip.scale),
                      let crop = strip.image.cropping(to: rect),
                      let pixels = ModernMenuBarItemImages.pixels(of: crop) else { continue }
                crops[entry.id] = crop
                let votes = ModernMenuBarItemImages.toneVotes(pixels: pixels, width: crop.width, height: crop.height)
                light += votes.light; dark += votes.dark
            }
            let tone: ModernMenuBarItemImages.GlyphTone? = light + dark == 0 ? nil : (light >= dark ? .light : .dark)
            for (id, crop) in crops {
                if let glyph = ModernMenuBarItemImages.glyph(from: crop, tone: tone, scale: strip.scale) {
                    result[id] = CapturedImage(image: glyph, scale: strip.scale)
                }
            }
        }
        return result
    }

    @concurrent
    private static func save(_ images: [String: CapturedImage], index: Data, directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        for (id, image) in images {
            guard let data = NSBitmapImageRep(cgImage: image.image).representation(using: .png, properties: [:]) else { continue }
            try data.write(to: directory.appendingPathComponent(ModernMenuBarItemImages.fileName(for: id)), options: .atomic)
        }
        try index.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
    }
}
