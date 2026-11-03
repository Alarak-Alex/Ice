import CoreGraphics
import Foundation

// Background removal adapted from Icey's GPL-3.0 ItemImages27 (0cb4b09c).
enum ModernMenuBarItemImages {
    enum GlyphTone: Sendable { case light, dark }

    static func cropRect(item: CGRect, strip: CGRect, scale: CGFloat) -> CGRect? {
        guard scale.isFinite, scale > 0, item.width > 0, item.height > 0,
              [item.minX, item.minY, item.width, item.height].allSatisfy(\.isFinite) else { return nil }
        let clipped = item.intersection(strip)
        guard !clipped.isNull, clipped.width >= item.width * 0.9, clipped.height >= item.height * 0.9 else { return nil }
        return CGRect(x: floor((clipped.minX - strip.minX) * scale), y: floor((clipped.minY - strip.minY) * scale),
                      width: ceil(clipped.width * scale), height: ceil(clipped.height * scale))
    }

    static func settled(_ before: CGRect, _ after: CGRect) -> Bool {
        guard !before.isNull, !after.isNull else { return false }
        return max(abs(before.minX - after.minX), abs(before.minY - after.minY),
                   abs(before.width - after.width), abs(before.height - after.height)) <= 1
    }

    static func pixels(of image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let success = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return success ? pixels : nil
    }

    static func background(pixels: [UInt8], width: Int, height: Int) -> [Double] {
        var counts = [UInt32: Int]()
        for y in 0..<height {
            for x in 0..<width where x == 0 || x == width - 1 || y == 0 || y == height - 1 {
                let i = (y * width + x) * 4
                let key = UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2])
                counts[key, default: 0] += 1
            }
        }
        let key = counts.max { $0.value < $1.value }?.key ?? 0
        return [Double((key >> 16) & 255), Double((key >> 8) & 255), Double(key & 255)]
    }

    static func toneVotes(pixels: [UInt8], width: Int, height: Int) -> (light: Int, dark: Int) {
        let base = background(pixels: pixels, width: width, height: height)
        var light = 0, dark = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            guard (0..<3).contains(where: { abs(Double(pixels[i + $0]) - base[$0]) >= 60 }) else { continue }
            if (0..<3).allSatisfy({ pixels[i + $0] >= 200 }) { light += 1 }
            if (0..<3).allSatisfy({ pixels[i + $0] <= 55 }) { dark += 1 }
        }
        return (light, dark)
    }

    /// Returns straight RGBA; callers premultiply once when constructing the CGImage.
    static func removingBackground(pixels: [UInt8], width: Int, height: Int, tone: GlyphTone?, scale: CGFloat = 1) -> [UInt8] {
        guard width > 0, height > 0, pixels.count == width * height * 4, scale.isFinite, scale > 0 else { return [] }
        let base = background(pixels: pixels, width: width, height: height)
        func edge(_ row: Int, _ columns: [Int]) -> (color: [Double], column: Int) {
            var best = (color: base, column: columns[0])
            var drift = Double.infinity
            for x in columns {
                let i = (row * width + x) * 4
                let color = (0..<3).map { Double(pixels[i + $0]) }
                let distance = (0..<3).map { abs(color[$0] - base[$0]) }.max()!
                if distance < drift { best = (color, x); drift = distance }
            }
            return best
        }
        let rawLeft = (0..<height).map { edge($0, Array(0..<min(2, width))) }
        let rawRight = (0..<height).map { edge($0, Array(max(0, width - 2)..<width)) }
        func clamped(_ edge: (color: [Double], column: Int)) -> (color: [Double], column: Int) {
            (0..<3).allSatisfy { abs(edge.color[$0] - base[$0]) <= 40 } ? edge : (base, edge.column)
        }
        let left = rawLeft.map(clamped), right = rawRight.map(clamped)
        func localBackground(_ i: Int, colored: Bool = false) -> [Double] {
            let row = i / 4 / width, x = i / 4 % width
            // Matching edges can identify a dark background band above a colored glyph.
            let agree = colored && (0..<3).allSatisfy { abs(rawLeft[row].color[$0] - rawRight[row].color[$0]) <= 12 }
            let l = agree ? rawLeft[row] : left[row], r = agree ? rawRight[row] : right[row]
            let span = r.column - l.column
            let share = span > 0 ? min(1, max(0, Double(x - l.column) / Double(span))) : 0
            return (0..<3).map { l.color[$0] + (r.color[$0] - l.color[$0]) * share }
        }
        var distances = [Double](repeating: 0, count: width * height)
        for pixel in distances.indices {
            let i = pixel * 4, local = localBackground(i)
            distances[pixel] = (0..<3).map { abs(Double(pixels[i + $0]) - local[$0]) }.max()!
        }
        let furthest = distances.max() ?? 0
        var result = pixels
        guard furthest > 8 else {
            for i in stride(from: 3, to: result.count, by: 4) { result[i] = 0 }
            return result
        }
        let far = distances.indices.filter { distances[$0] >= furthest * 0.5 }
        var white = (count: 0, sum: [0.0, 0.0, 0.0]), black = white
        let contrasting = distances.indices.filter { distances[$0] > 16 }
        let colorful = contrasting.filter { pixel in
            let channels = (0..<3).map { pixels[pixel * 4 + $0] }
            return Int(channels.max()!) - Int(channels.min()!) >= 60
        }.count
        // shortcut: wide colored metrics use the conservative mask until native glyph snapshots are available.
        let isColored = width <= height * 3 && colorful >= 4 && Double(colorful) >= Double(contrasting.count) * 0.3
        var colorSpans = [ClosedRange<Int>?](repeating: nil, count: height)
        if isColored {
            var rows = [ClosedRange<Int>?](repeating: nil, count: height)
            for pixel in contrasting {
                let channels = (0..<3).map { pixels[pixel * 4 + $0] }
                guard Int(channels.max()!) - Int(channels.min()!) >= 40 else { continue }
                let y = pixel / width, x = pixel % width
                rows[y] = rows[y].map { min($0.lowerBound, x)...max($0.upperBound, x) } ?? x...x
            }
            let margin = max(1, Int(min(CGFloat(max(width, height)), scale.rounded())))
            for y in 0..<height {
                let nearby = rows[max(0, y - margin)...min(height - 1, y + margin)].compactMap { $0 }
                if let first = nearby.map(\.lowerBound).min(), let last = nearby.map(\.upperBound).max() {
                    colorSpans[y] = max(0, first - margin)...min(width - 1, last + margin)
                }
            }
            // shortcut: mixed white badges fall back to app icons until native glyph snapshots are available.
            for pixel in distances.indices where colorSpans[pixel / width]?.contains(pixel % width) != true {
                let i = pixel * 4
                if distances[pixel] > 32 && (0..<3).allSatisfy({ pixels[i + $0] >= 200 }) { return [] }
            }
        }
        for pixel in far {
            let i = pixel * 4
            if (0..<3).allSatisfy({ pixels[i + $0] >= 200 }) {
                white.count += 1
                for c in 0..<3 { white.sum[c] += Double(pixels[i + c]) }
            } else if (0..<3).allSatisfy({ pixels[i + $0] <= 55 }) {
                black.count += 1
                for c in 0..<3 { black.sum[c] += Double(pixels[i + c]) }
            }
        }
        let dominant = tone.map { $0 == .light ? white : black } ?? (white.count >= black.count ? white : black)
        // A white highlight inside Siri's colored orb is not the color of the whole glyph.
        let glyph = !isColored &&
            dominant.count >= 4 && (tone != nil || Double(dominant.count) >= Double(far.count) * 0.2)
            ? dominant.sum.map { $0 / Double(dominant.count) } : nil
        let contrast = glyph.map { glyph in (0..<3).map { abs(glyph[$0] - base[$0]) }.max()! } ?? 0
        for pixel in distances.indices {
            let i = pixel * 4
            if isColored && colorSpans[pixel / width]?.contains(pixel % width) != true {
                result[i + 3] = 0
                continue
            }
            let local = localBackground(i, colored: isColored)
            let distance = isColored ? (0..<3).map { abs(Double(pixels[i + $0]) - local[$0]) }.max()! : distances[pixel]
            var alpha = isColored
                ? min(1, max(0, (distance - 8) / 24))
                : min(1, distance / furthest)
            if let glyph, contrast > 8 {
                let distance = (0..<3).map { abs(Double(pixels[i + $0]) - glyph[$0]) }.max()!
                alpha = min(1, max(0, (1 - distance / contrast - 0.25) / 0.75))
            }
            guard alpha > 0.06 else { result[i + 3] = 0; continue }
            result[i + 3] = UInt8((alpha * 255).rounded())
            for c in 0..<3 {
                result[i + c] = UInt8(min(255, max(0, ((Double(pixels[i + c]) - local[c] * (1 - alpha)) / alpha).rounded())))
            }
        }
        return result
    }

    static func droppingFaintMarks(_ pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
        var result = pixels
        var visited = [Bool](repeating: false, count: width * height)
        for start in visited.indices where !visited[start] && pixels[start * 4 + 3] > 16 {
            var mark = [start], cursor = 0
            var strongest = pixels[start * 4 + 3]
            visited[start] = true
            while cursor < mark.count {
                let pixel = mark[cursor]; cursor += 1
                let x = pixel % width, y = pixel / width
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let next = ny * width + nx
                        guard !visited[next], pixels[next * 4 + 3] > 16 else { continue }
                        visited[next] = true
                        strongest = max(strongest, pixels[next * 4 + 3])
                        mark.append(next)
                    }
                }
            }
            if strongest < 160 { for pixel in mark { result[pixel * 4 + 3] = 0 } }
        }
        return result
    }

    static func glyph(from image: CGImage, tone: GlyphTone?, scale: CGFloat = 1) -> CGImage? {
        guard scale.isFinite, scale > 0, let pixels = pixels(of: image) else { return nil }
        let width = image.width, height = image.height
        let removed = removingBackground(pixels: pixels, width: width, height: height, tone: tone, scale: scale)
        let alphas = stride(from: 3, to: removed.count, by: 4).map { removed[$0] }
        let ink = alphas.filter { $0 > 200 }.count
        let haze = alphas.filter { $0 > 16 && $0 <= 200 }.count
        guard ink > 0, haze <= ink * 3 else { return nil }
        var clean = droppingFaintMarks(removed, width: width, height: height)
        var bounds = CGRect.null
        var cleanInk = 0, cleanHaze = 0
        for pixel in 0..<(width * height) where clean[pixel * 4 + 3] > 16 {
            bounds = bounds.union(CGRect(x: pixel % width, y: pixel / width, width: 1, height: 1))
            if clean[pixel * 4 + 3] > 200 { cleanInk += 1 } else { cleanHaze += 1 }
        }
        guard !bounds.isNull else { return nil }
        // Icey's quality thresholds include the glyph's 11pt margin on both sides.
        let paddedArea = Double((bounds.width + 22 * scale) * CGFloat(height))
        guard Double(cleanInk) / paddedArea <= 0.45, Double(cleanHaze) / paddedArea <= 0.15 else { return nil }
        for i in stride(from: 0, to: clean.count, by: 4) {
            for c in 0..<3 { clean[i + c] = UInt8((Double(clean[i + c]) * Double(clean[i + 3]) / 255).rounded()) }
        }
        return clean.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()?.cropping(to: bounds)
        }
    }

    static func fileName(for id: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 { hash ^= UInt64(byte); hash &*= 0x0000_0100_0000_01b3 }
        return String(format: "%016llx.png", hash)
    }
}
