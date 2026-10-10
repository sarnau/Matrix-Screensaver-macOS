import CoreGraphics
import CoreText
import Foundation
import Metal
import os

private let logger = Logger(subsystem: "com.sarnau.MatrixRain", category: "GlyphAtlas")

/// The rain's glyph shapes, rasterised once with CoreText into an 8 × 9 grid of 64 px cells.
/// Glyphs are mirrored horizontally, as in the film, and centred so they fit the shader's
/// 60 % horizontal sample window (which matches the 0.6 aspect of a screen cell).
final class GlyphAtlas {
    static let columns = 8
    static let rows = 9
    static let cellPixels = 64
    static let glyphCount = columns * rows
    static let width = columns * cellPixels
    static let height = rows * cellPixels
    static let sampleWindow: ClosedRange<Double> = 0.2...0.8
    static let fontSize: CGFloat = 46
    static let primaryFontName = "HiraginoSans-W3"
    static let fallbackFontName = "Menlo-Regular"

    /// 56 half-width katakana (U+FF66–U+FF9D), 10 digits, 6 symbols.
    static let primaryCharacters: [Character] = {
        let katakana = (0xFF66...0xFF9D).compactMap { Unicode.Scalar(UInt32($0)).map(Character.init) }
        return katakana + Array("0123456789") + Array(":.=*+-")
    }()

    /// ASCII-only set for when Hiragino is unavailable, repeated to fill all 72 cells.
    static let fallbackCharacters: [Character] = {
        let base = Array("0123456789:.=*+-ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return (0..<glyphCount).map { base[$0 % base.count] }
    }()

    struct Bitmap {
        let pixels: [UInt8]       // width × height, 8-bit coverage, row 0 = top
        let usedFallback: Bool
    }

    let texture: any MTLTexture
    let usedFallbackFont: Bool

    init?(device: any MTLDevice, commandQueue: any MTLCommandQueue) {
        guard let bitmap = Self.rasterize() else {
            logger.error("Could not rasterise glyph atlas")
            return nil
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: Self.width, height: Self.height, mipmapped: true)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            logger.error("Could not create glyph atlas texture")
            return nil
        }
        let uploaded = bitmap.pixels.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            texture.replace(region: MTLRegionMake2D(0, 0, Self.width, Self.height),
                            mipmapLevel: 0, withBytes: base, bytesPerRow: Self.width)
            return true
        }
        guard uploaded,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            logger.error("Could not upload glyph atlas")
            return nil
        }
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if bitmap.usedFallback {
            logger.notice("Hiragino Sans unavailable; using Menlo fallback glyphs")
        }
        self.texture = texture
        self.usedFallbackFont = bitmap.usedFallback
    }

    /// Hiragino with katakana if it is installed and covers every character, otherwise Menlo with ASCII.
    static func rasterize() -> Bitmap? {
        if let font = font(named: primaryFontName),
           covers(font, primaryCharacters),
           let pixels = render(primaryCharacters, font: font) {
            return Bitmap(pixels: pixels, usedFallback: false)
        }
        guard let font = font(named: fallbackFontName),
              let pixels = render(fallbackCharacters, font: font) else { return nil }
        return Bitmap(pixels: pixels, usedFallback: true)
    }

    /// The named font, or nil if CoreText substituted a different one.
    static func font(named name: String) -> CTFont? {
        let font = CTFontCreateWithName(name as CFString, fontSize, nil)
        return (CTFontCopyPostScriptName(font) as String) == name ? font : nil
    }

    static func render(_ characters: [Character], font: CTFont) -> [UInt8]? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(false)

        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        let half = CGFloat(cellPixels) / 2
        for (index, character) in characters.prefix(glyphCount).enumerated() {
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: String(character), attributes: attributes))
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let column = index % columns
            let row = index / columns
            // CoreGraphics' origin is bottom-left; atlas row 0 is the top.
            let centerX = CGFloat(column * cellPixels) + half
            let centerY = CGFloat(height - row * cellPixels) - half

            context.saveGState()
            context.translateBy(x: centerX, y: centerY)
            context.scaleBy(x: -1, y: 1)   // mirrored, as in the film
            context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
            CTLineDraw(line, context)
            context.restoreGState()
        }

        guard let data = context.data else { return nil }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height))
    }

    private static func covers(_ font: CTFont, _ characters: [Character]) -> Bool {
        let utf16 = characters.flatMap { Array(String($0).utf16) }
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        return CTFontGetGlyphsForCharacters(font, utf16, &glyphs, utf16.count)
    }
}
