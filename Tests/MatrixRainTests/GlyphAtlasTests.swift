import XCTest
import Metal
@testable import MatrixRainHost

final class GlyphAtlasTests: XCTestCase {
    func testCharacterSetsHave72Glyphs() {
        XCTAssertEqual(GlyphAtlas.glyphCount, 72)
        XCTAssertEqual(GlyphAtlas.primaryCharacters.count, 72)
        XCTAssertEqual(GlyphAtlas.fallbackCharacters.count, 72)
        XCTAssertEqual(GlyphAtlas.primaryCharacters.first, "ｦ")
        XCTAssertEqual(GlyphAtlas.primaryCharacters[55], "ﾝ")
    }

    func testRasterizeUsesHiragino() throws {
        let bitmap = try XCTUnwrap(GlyphAtlas.rasterize())
        XCTAssertFalse(bitmap.usedFallback)
        XCTAssertEqual(bitmap.pixels.count, GlyphAtlas.width * GlyphAtlas.height)
    }

    func testEveryCellHasInkInsideSampleWindow() throws {
        let primary = try XCTUnwrap(GlyphAtlas.rasterize()).pixels
        let menlo = try XCTUnwrap(GlyphAtlas.font(named: GlyphAtlas.fallbackFontName))
        let fallback = try XCTUnwrap(GlyphAtlas.render(GlyphAtlas.fallbackCharacters, font: menlo))
        for (name, pixels) in [("primary", primary), ("fallback", fallback)] {
            for glyph in 0..<GlyphAtlas.glyphCount {
                let (inside, outside) = ink(in: pixels, glyph: glyph)
                XCTAssertGreaterThan(inside, 2_000, "\(name) glyph \(glyph) has no ink")
                XCTAssertLessThan(outside, inside / 50, "\(name) glyph \(glyph) spills outside the sample window")
            }
        }
    }

    func testTextureIsMipmappedAtlasSize() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let atlas = try XCTUnwrap(GlyphAtlas(device: device, commandQueue: queue))
        XCTAssertEqual(atlas.texture.width, 512)
        XCTAssertEqual(atlas.texture.height, 576)
        XCTAssertEqual(atlas.texture.pixelFormat, .r8Unorm)
        XCTAssertEqual(atlas.texture.mipmapLevelCount, 10)
        XCTAssertFalse(atlas.usedFallbackFont)
    }

    /// Sums of pixel values inside and outside the horizontal sample window of one atlas cell.
    private func ink(in pixels: [UInt8], glyph: Int) -> (inside: Int, outside: Int) {
        let cell = GlyphAtlas.cellPixels
        let x0 = (glyph % GlyphAtlas.columns) * cell
        let y0 = (glyph / GlyphAtlas.columns) * cell
        let lo = Int(GlyphAtlas.sampleWindow.lowerBound * Double(cell))
        let hi = Int(GlyphAtlas.sampleWindow.upperBound * Double(cell))
        var inside = 0, outside = 0
        for y in y0..<(y0 + cell) {
            for x in x0..<(x0 + cell) {
                let v = Int(pixels[y * GlyphAtlas.width + x])
                if (lo..<hi).contains(x - x0) { inside += v } else { outside += v }
            }
        }
        return (inside, outside)
    }
}
