import XCTest
import ImageIO
@testable import MatrixRainHost

/// System Settings shows a third-party screensaver's tile from these bundle resources.
final class ThumbnailTests: XCTestCase {
    private func pixelSize(of name: String) throws -> CGSize {
        let url = try XCTUnwrap(Bundle(for: MatrixRainView.self).url(forResource: name, withExtension: "png"),
                                "\(name).png missing from the bundle")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }

    func testBundleShipsSettingsThumbnails() throws {
        XCTAssertEqual(try pixelSize(of: "thumbnail"), CGSize(width: 90, height: 58))
        XCTAssertEqual(try pixelSize(of: "thumbnail@2x"), CGSize(width: 180, height: 116))
    }
}
