import XCTest
@testable import MatrixRainHost

final class GridMetricsTests: XCTestCase {
    func testRetinaDefaultGlyphSize() {
        let m = GridMetrics(pixelSize: CGSize(width: 3024, height: 1964), backingScale: 2, glyphSize: 22, isPreview: false)
        XCTAssertEqual(m.cellHeight, 44, accuracy: 1e-9)
        XCTAssertEqual(m.cellWidth, 26.4, accuracy: 1e-9)
        XCTAssertEqual(m.columns, 115)   // 3024 / 26.4 = 114.5 → 115
        XCTAssertEqual(m.rows, 45)       // 1964 / 44 = 44.6 → 45
    }

    func testSmallerGlyphsMeanSmallerCells() {
        let m = GridMetrics(pixelSize: CGSize(width: 1920, height: 1080), backingScale: 1, glyphSize: 11, isPreview: false)
        XCTAssertEqual(m.cellHeight, 11, accuracy: 1e-9)
        XCTAssertEqual(m.columns, 291)   // 1920 / 6.6 = 290.9
        XCTAssertEqual(m.rows, 99)       // 1080 / 11 = 98.2
    }

    func testPreviewUsesSmallerCells() {
        let m = GridMetrics(pixelSize: CGSize(width: 600, height: 376), backingScale: 2, glyphSize: 22, isPreview: true)
        XCTAssertEqual(m.cellHeight, 15.4, accuracy: 1e-9)  // 22 × 0.35 × 2
        XCTAssertEqual(m.columns, 65)
        XCTAssertEqual(m.rows, 25)
    }

    func testCellHeightNeverBelowMinimum() {
        let m = GridMetrics(pixelSize: CGSize(width: 100, height: 100), backingScale: 1, glyphSize: 0.01, isPreview: true)
        XCTAssertEqual(m.cellHeight, GridMetrics.minimumCellHeightPixels)
    }

    func testDegenerateSizes() {
        let zero = GridMetrics(pixelSize: .zero, backingScale: 2, glyphSize: 22, isPreview: false)
        XCTAssertEqual(zero.columns, 1)
        XCTAssertEqual(zero.rows, 1)

        let nan = GridMetrics(pixelSize: CGSize(width: CGFloat.nan, height: -50), backingScale: .nan, glyphSize: .nan, isPreview: false)
        XCTAssertEqual(nan.columns, 1)
        XCTAssertEqual(nan.rows, 1)
        XCTAssertEqual(nan.cellHeight, 22, accuracy: 1e-9)   // scale falls back to 1, glyph size to 22 pt
    }
}
