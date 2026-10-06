import XCTest
@testable import MatrixRainHost

final class SettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MatrixRainTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testEmptyDefaultsLoadDefaults() {
        let s = Settings.load(from: defaults)
        XCTAssertEqual(s, Settings())
        XCTAssertEqual(s.speed, 1.0)
        XCTAssertEqual(s.glyphSize, 22)
        XCTAssertEqual(s.color, Settings.RGB(red: 0, green: 1, blue: 0x41 / 255))
        XCTAssertTrue(s.bloom)
    }

    func testRoundTrip() {
        let original = Settings(speed: 2.5, glyphSize: 30, color: .init(red: 0.2, green: 0.4, blue: 0.9), bloom: false)
        original.save(to: defaults)
        XCTAssertEqual(Settings.load(from: defaults), original)
    }

    func testOutOfRangeValuesAreClamped() {
        let s = Settings(speed: 10, glyphSize: 5, color: .init(red: -1, green: 2, blue: 0.5))
        XCTAssertEqual(s.speed, 3.0)
        XCTAssertEqual(s.glyphSize, 12)
        XCTAssertEqual(s.color, .init(red: 0, green: 1, blue: 0.5))

        defaults.set(0.01, forKey: Settings.Keys.speed)
        defaults.set(99.0, forKey: Settings.Keys.glyphSize)
        let loaded = Settings.load(from: defaults)
        XCTAssertEqual(loaded.speed, 0.25)
        XCTAssertEqual(loaded.glyphSize, 44)
    }

    func testNonFiniteValuesFallBackToDefaults() {
        let s = Settings(speed: .nan, glyphSize: .infinity, color: .init(red: .nan, green: 0.5, blue: -.infinity))
        XCTAssertEqual(s.speed, Settings.defaultSpeed)
        XCTAssertEqual(s.glyphSize, Settings.defaultGlyphSize)
        XCTAssertEqual(s.color.red, Settings.defaultColor.red)
        XCTAssertEqual(s.color.green, 0.5)
        XCTAssertEqual(s.color.blue, Settings.defaultColor.blue)
    }

    func testLegacyDensityIsConvertedToGlyphSize() {
        defaults.set(1.25, forKey: Settings.Keys.legacyDensity)
        XCTAssertEqual(Settings.load(from: defaults).glyphSize, 17.6, accuracy: 1e-9)   // 22 pt / 1.25
        defaults.set(2.0, forKey: Settings.Keys.legacyDensity)
        XCTAssertEqual(Settings.load(from: defaults).glyphSize, 12)                     // 11 pt, clamped
        defaults.set(30.0, forKey: Settings.Keys.glyphSize)
        XCTAssertEqual(Settings.load(from: defaults).glyphSize, 30, "an explicit glyph size wins")
    }

    func testWrongTypeFallsBackToDefault() {
        defaults.set("fast", forKey: Settings.Keys.speed)
        defaults.set(["x"], forKey: Settings.Keys.colorGreen)
        defaults.set("yes", forKey: Settings.Keys.bloom)
        let s = Settings.load(from: defaults)
        XCTAssertEqual(s.speed, Settings.defaultSpeed)
        XCTAssertEqual(s.color.green, Settings.defaultColor.green)
        XCTAssertEqual(s.bloom, Settings.defaultBloom)
    }

    func testLinearColor() {
        let c = Settings().linearColor
        XCTAssertEqual(c.x, 0, accuracy: 1e-6)
        XCTAssertEqual(c.y, 1, accuracy: 1e-6)
        XCTAssertEqual(c.z, 0.0529, accuracy: 1e-3)   // sRGB 0x41 → linear
    }
}
