// Compile with ModernMenuBarItemImages.swift. Uses synthetic pixels, never screen capture.
import CoreGraphics
import Foundation

@main
struct ModernItemImagesRegression {
    static func main() {
        let strip = CGRect(x: -1512, y: 98, width: 1512, height: 33)
        assert(ModernMenuBarItemImages.cropRect(item: CGRect(x: -442, y: 102.5, width: 33, height: 24),
                                              strip: strip, scale: 2) == CGRect(x: 2140, y: 9, width: 66, height: 48))
        assert(ModernMenuBarItemImages.cropRect(item: CGRect(x: -1530, y: 98, width: 33, height: 24), strip: strip, scale: 2) == nil)
        assert(ModernMenuBarItemImages.cropRect(item: CGRect(x: -442, y: 128, width: 33, height: 24), strip: strip, scale: 2) == nil)
        assert(ModernMenuBarItemImages.cropRect(item: .null, strip: strip, scale: 2) == nil)
        let frame = CGRect(x: 20, y: 0, width: 24, height: 24)
        assert(ModernMenuBarItemImages.settled(frame, frame.offsetBy(dx: 1, dy: 0)))
        assert(!ModernMenuBarItemImages.settled(frame, frame.offsetBy(dx: 2, dy: 0)))
        assert(!ModernMenuBarItemImages.settled(frame, .null))

        let width = 40, height = 40
        func tile(glyph: Bool, gradient: Bool = false, light: Bool = true, color: Bool = false) -> [UInt8] {
            var pixels = [UInt8](repeating: 255, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    let base = gradient ? 90 + y / 2 + x / 4 : 120
                    for c in 0..<3 { pixels[i + c] = UInt8(base) }
                    if glyph && (18..<22).contains(x) && (10..<30).contains(y) {
                        pixels[i] = color ? 240 : (light ? 255 : 0)
                        pixels[i + 1] = color ? 60 : pixels[i]
                        pixels[i + 2] = color ? 80 : pixels[i]
                    }
                }
            }
            return pixels
        }
        func image(_ pixels: [UInt8], width: Int = 40, height: Int = 40) -> CGImage {
            let data = Data(pixels)
            let provider = CGDataProvider(data: data as CFData)!
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        }
        for light in [true, false] {
            let source = tile(glyph: true, gradient: true, light: light)
            let clean = ModernMenuBarItemImages.removingBackground(pixels: source, width: width, height: height,
                                                                 tone: light ? .light : .dark)
            assert(clean[(20 * width + 19) * 4 + 3] > 240, "Solid strokes must survive a textured bar")
            assert(clean[(15 * width + 5) * 4 + 3] == 0, "The row's gradient must not become glyph")
            let result = ModernMenuBarItemImages.glyph(from: image(source), tone: light ? .light : .dark)
            assert(result?.width == 4 && result?.height == 20, "The final image must trim the bar's uneven padding")
        }
        assert(ModernMenuBarItemImages.glyph(from: image(tile(glyph: false)), tone: nil) == nil,
               "A background-only crop must never replace a real cached icon")
        let colored = ModernMenuBarItemImages.glyph(from: image(tile(glyph: true, color: true)), tone: nil)!
        let coloredPixels = ModernMenuBarItemImages.pixels(of: colored)!
        assert(coloredPixels[0] > coloredPixels[1] + 100, "Color icons must retain their color")
        var highlightedColor = tile(glyph: true, color: true)
        for y in 18..<22 {
            let i = (y * width + 19) * 4
            for c in 0..<3 { highlightedColor[i + c] = 255 }
        }
        let withHighlight = ModernMenuBarItemImages.glyph(from: image(highlightedColor), tone: .light)!
        assert(withHighlight.width == 4 && withHighlight.height == 20,
               "A global white glyph tone must not erase a colored icon around its white highlight")
        let highlightPixels = ModernMenuBarItemImages.pixels(of: withHighlight)!
        assert(highlightPixels[0] > highlightPixels[1] + 100)
        var pastel = tile(glyph: false)
        for y in 10..<30 {
            for x in 18..<22 {
                let i = (y * width + x) * 4
                pastel[i] = 160; pastel[i + 1] = 110; pastel[i + 2] = 170
            }
        }
        for y in 18..<22 {
            let i = (y * width + 19) * 4
            for c in 0..<3 { pastel[i + c] = 255 }
        }
        let pastelImage = ModernMenuBarItemImages.glyph(from: image(pastel), tone: .light)
        assert(pastelImage?.width == 4 && pastelImage?.height == 20,
               "Pastel colored bodies must not be classified as a fade around a white highlight")
        var plate = tile(glyph: false)
        for y in 5..<35 {
            for x in 5..<35 {
                let i = (y * width + x) * 4
                for c in 0..<3 { plate[i + c] = 255 }
            }
        }
        assert(ModernMenuBarItemImages.glyph(from: image(plate), tone: .light, scale: 2)?.width == 30,
               "A filled status icon must not be rejected using thresholds calibrated for a padded tile")
        var banded = tile(glyph: false)
        for y in 0..<40 {
            for x in 0..<40 {
                let i = (y * 40 + x) * 4
                if y < 10 { for c in 0..<3 { banded[i + c] = 0 } }
                if (8..<32).contains(x) && (12..<36).contains(y) {
                    banded[i] = 240; banded[i + 1] = 60; banded[i + 2] = 80
                }
            }
        }
        let bandedImage = ModernMenuBarItemImages.glyph(from: image(banded), tone: .light, scale: 2)
        assert(bandedImage?.width == 24 && bandedImage?.height == 24,
               "A dark band whose two edges agree must not remain behind a colored glyph")
        var diagonal = tile(glyph: false)
        for y in 0..<40 {
            for x in 0..<40 {
                let i = (y * 40 + x) * 4
                if x < 28 - y { for c in 0..<3 { diagonal[i + c] = 3 } }
                if hypot(Double(x - 20), Double(y - 22)) < 14 {
                    diagonal[i] = 240; diagonal[i + 1] = 60; diagonal[i + 2] = 80
                }
            }
        }
        let diagonalImage = ModernMenuBarItemImages.glyph(from: image(diagonal), tone: .light, scale: 2)!
        assert(diagonalImage.width <= 32 && diagonalImage.height <= 32,
               "A tight colored glyph must not keep the diagonal wallpaper above or beside it")
        var whiteBadge = plate
        for y in 10..<30 {
            for x in 10..<30 {
                let i = (y * width + x) * 4
                whiteBadge[i] = 240; whiteBadge[i + 1] = 60; whiteBadge[i + 2] = 80
            }
        }
        assert(ModernMenuBarItemImages.glyph(from: image(whiteBadge), tone: .light) == nil,
               "An uncertain white badge must fall back instead of being cropped into an incomplete icon")
        var wide = [UInt8](repeating: 255, count: 240 * 40 * 4)
        for y in 0..<40 {
            for x in 0..<240 {
                let i = (y * 240 + x) * 4
                for c in 0..<3 { wide[i + c] = 120 }
                if (x < 80 || x >= 160) && x % 4 < 2 && (10..<30).contains(y) {
                    wide[i] = 20; wide[i + 1] = 230; wide[i + 2] = 50
                }
                let distance = hypot(Double(x - 120), Double(y - 20))
                if distance < 18 {
                    let moon = UInt8(170 + (1 - distance / 18) * 85)
                    for c in 0..<3 { wide[i + c] = moon }
                }
            }
        }
        assert(ModernMenuBarItemImages.glyph(from: image(wide, width: 240), tone: .light, scale: 2) == nil,
               "A colored metric item must not store a photographic patch of wallpaper as its glyph")
        var faint = [UInt8](repeating: 0, count: width * height * 4)
        faint[(5 * width + 5) * 4 + 3] = 100
        faint[(20 * width + 20) * 4 + 3] = 255
        faint[(21 * width + 20) * 4 + 3] = 100
        let cleaned = ModernMenuBarItemImages.droppingFaintMarks(faint, width: width, height: height)
        assert(cleaned[(5 * width + 5) * 4 + 3] == 0)
        assert(cleaned[(21 * width + 20) * 4 + 3] == 100, "Soft edges connected to a solid stroke must survive")
        let name = ModernMenuBarItemImages.fileName(for: "status:example/../../::Item-0")
        assert(!name.contains("/") && name.hasSuffix(".png"))
        assert(name == ModernMenuBarItemImages.fileName(for: "status:example/../../::Item-0"))
        print("Modern images: Retina/multi-display crops, stable frames, gradient/diagonal background removal, colored highlights, empty/uncertain photos, glyph trimming, faint marks and safe cache names passed")
    }
}
