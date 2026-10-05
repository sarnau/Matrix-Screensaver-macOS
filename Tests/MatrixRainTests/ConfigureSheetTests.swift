import XCTest
@testable import MatrixRainHost

@MainActor
final class ConfigureSheetTests: XCTestCase {
    func testControlsRoundTripSettings() {
        let controller = ConfigureSheetController { _ in }
        let original = Settings(speed: 2.25, density: 0.75, color: .init(red: 0.1, green: 0.6, blue: 0.3), bloom: false)
        controller.load(original)
        let edited = controller.editedSettings
        XCTAssertEqual(edited.speed, 2.25, accuracy: 1e-9)
        XCTAssertEqual(edited.density, 0.75, accuracy: 1e-9)
        XCTAssertEqual(edited.color.red, 0.1, accuracy: 1e-4)
        XCTAssertEqual(edited.color.green, 0.6, accuracy: 1e-4)
        XCTAssertEqual(edited.color.blue, 0.3, accuracy: 1e-4)
        XCTAssertFalse(edited.bloom)
    }

    func testSheetIsLargeEnoughForItsContent() throws {
        let controller = ConfigureSheetController { _ in }
        let content = try XCTUnwrap(controller.window.contentView)
        content.layoutSubtreeIfNeeded()
        let needed = content.fittingSize
        let available = controller.window.contentLayoutRect.size
        XCTAssertGreaterThanOrEqual(available.width, needed.width)
        XCTAssertGreaterThanOrEqual(available.height, needed.height)
    }

    func testSliderRangesMatchSettings() {
        let controller = ConfigureSheetController { _ in }
        XCTAssertEqual(controller.speedSlider.minValue, Settings.speedRange.lowerBound)
        XCTAssertEqual(controller.speedSlider.maxValue, Settings.speedRange.upperBound)
        XCTAssertEqual(controller.densitySlider.minValue, Settings.densityRange.lowerBound)
        XCTAssertEqual(controller.densitySlider.maxValue, Settings.densityRange.upperBound)
    }

    func testOKSavesEditedValues() {
        var saved: [Settings] = []
        let controller = ConfigureSheetController { saved.append($0) }
        _ = controller.present(settings: Settings())
        controller.speedSlider.doubleValue = 2.5
        controller.bloomCheckbox.state = .off
        controller.ok(nil)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.speed ?? 0, 2.5, accuracy: 1e-9)
        XCTAssertEqual(saved.first?.bloom, false)
    }

    func testCancelDiscardsEdits() {
        var saved: [Settings] = []
        let controller = ConfigureSheetController { saved.append($0) }
        _ = controller.present(settings: Settings())
        controller.speedSlider.doubleValue = 2.5
        controller.cancel(nil)
        XCTAssertTrue(saved.isEmpty)
        // Re-presenting shows the stored settings, not the discarded edit.
        _ = controller.present(settings: Settings())
        XCTAssertEqual(controller.speedSlider.doubleValue, 1.0, accuracy: 1e-9)
    }

    func testViewSheetAppliesSettings() throws {
        let name = "MatrixRainTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let view = try XCTUnwrap(MatrixRainView(frame: NSRect(x: 0, y: 0, width: 200, height: 100),
                                                isPreview: true, defaults: defaults))
        XCTAssertTrue(view.hasConfigureSheet)
        XCTAssertNotNil(view.configureSheet)
        view.configureController.densitySlider.doubleValue = 1.75
        view.configureController.ok(nil)
        XCTAssertEqual(view.currentSettings.density, 1.75, accuracy: 1e-9)
        XCTAssertEqual(Settings.load(from: defaults).density, 1.75, accuracy: 1e-9)
    }
}
