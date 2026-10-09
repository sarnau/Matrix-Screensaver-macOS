import XCTest
import ImageIO
@testable import MatrixRainHost

/// System Settings shows a third-party screensaver's tile from these bundle resources.
final class ThumbnailTests: XCTestCase {
    /// On macOS 27 our plain PNG pair got the generic placeholder tile while Flying Toasters' multi-resolution
    /// thumbnail.tiff shows, so ship the TIFF Xcode builds from thumbnail.png + thumbnail@2x.png.
    func testBundleShipsMultiResolutionThumbnailTIFF() throws {
        let url = try XCTUnwrap(Bundle(for: MatrixRainView.self).url(forResource: "thumbnail", withExtension: "tiff"),
                                "thumbnail.tiff missing from the bundle")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let sizes = (0..<CGImageSourceGetCount(source)).compactMap { index in
            CGImageSourceCreateImageAtIndex(source, index, nil).map { CGSize(width: $0.width, height: $0.height) }
        }
        XCTAssertEqual(Set(sizes.map { "\(Int($0.width))x\(Int($0.height))" }), ["90x58", "180x116"])
    }
}
