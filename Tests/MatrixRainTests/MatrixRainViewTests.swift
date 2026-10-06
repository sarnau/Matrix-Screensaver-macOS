import XCTest
@testable import MatrixRainHost

@MainActor
final class MatrixRainViewTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "MatrixRainTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    private func makeView(isPreview: Bool = false) throws -> MatrixRainView {
        try XCTUnwrap(MatrixRainView(frame: NSRect(x: 0, y: 0, width: 400, height: 300),
                                     isPreview: isPreview, defaults: makeDefaults()))
    }

    func testCreatesRendererAndMetalLayer() throws {
        let view = try makeView()
        XCTAssertTrue(view.hasRenderer)
        XCTAssertTrue(view.layer is CAMetalLayer)
        XCTAssertFalse(view.isRendering)
    }

    func testStartAndStopAreIdempotent() throws {
        let view = try makeView()
        view.startAnimation()
        view.startAnimation()
        XCTAssertTrue(view.isRendering)
        view.stopAnimation()
        view.stopAnimation()
        XCTAssertFalse(view.isRendering)
    }

    func testStopReleasesSurfacesAndRestartRendersAgain() throws {
        let view = try makeView()
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.startAnimation()
        XCTAssertTrue(view.rendererHasSurfaces)
        view.stopAnimation()
        XCTAssertFalse(view.rendererHasSurfaces, "stopped instances must not keep full-size GPU textures")
        view.startAnimation()
        XCTAssertTrue(view.isRendering)
        XCTAssertTrue(view.rendererHasSurfaces)
    }

    func testInstancesStartAtDifferentPointsInTheRain() throws {
        let a = try makeView()
        let b = try makeView()
        a.startAnimation()
        b.startAnimation()
        XCTAssertNotEqual(a.timeOffset, b.timeOffset, "displays would show identical rain")
        XCTAssertTrue((0..<MatrixRainView.timeWrap).contains(a.timeOffset))
    }

    func testRemovingFromWindowStopsRendering() throws {
        let view = try makeView()
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.startAnimation()
        XCTAssertTrue(view.isRendering)
        window.contentView = nil
        XCTAssertFalse(view.isRendering)
    }

    func testResizeReachesRenderer() throws {
        let view = try makeView()
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        let before = try XCTUnwrap(view.rendererMetrics).columns
        view.setFrameSize(NSSize(width: 800, height: 300))
        XCTAssertGreaterThan(try XCTUnwrap(view.rendererMetrics).columns, before)
    }

    func testApplyPersistsAndUpdatesRenderer() throws {
        let defaults = makeDefaults()
        let view = try XCTUnwrap(MatrixRainView(frame: NSRect(x: 0, y: 0, width: 400, height: 300),
                                                isPreview: true, defaults: defaults))
        view.apply(Settings(speed: 2, bloom: false))
        XCTAssertEqual(view.currentSettings.speed, 2)
        XCTAssertEqual(Settings.load(from: defaults).speed, 2)
        XCTAssertFalse(Settings.load(from: defaults).bloom)
    }

    func testLoadsSavedSettings() throws {
        let defaults = makeDefaults()
        Settings(glyphSize: 30).save(to: defaults)
        let view = try XCTUnwrap(MatrixRainView(frame: .zero, isPreview: false, defaults: defaults))
        XCTAssertEqual(view.currentSettings.glyphSize, 30)
    }
}
