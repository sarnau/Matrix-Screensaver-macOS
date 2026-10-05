# Matrix Rain Screensaver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `MatrixRain.saver`, a macOS 14+ screensaver in Swift that renders film-accurate Matrix digital rain with Metal, plus a host app for development and an XCTest suite.

**Architecture:** A full-screen fragment shader computes each grid cell's glyph and brightness procedurally from `(column, row, time)` with integer hashes; the CPU only uploads a 64-byte uniforms struct per frame. Glyph shapes come from a CoreText-rasterised atlas texture; bloom is downsample → `MPSImageGaussianBlur` → additive composite with tone mapping. A `ScreenSaverView` subclass owns a `CAMetalLayer` and drives frames with `NSView.displayLink`.

**Tech Stack:** Swift 6 (strict concurrency), Metal / MSL, MetalPerformanceShaders, CoreText, AppKit, ScreenSaver.framework, XCTest, XcodeGen 2.46.

**Spec:** `docs/superpowers/specs/2026-10-06-matrix-screensaver-design.md`

## Global Constraints

- Deployment target: macOS 14.0. Universal binary (`arm64` + `x86_64`) in Release.
- `SWIFT_VERSION` = 6.0 (Swift 6 language mode, complete concurrency checking). Builds must produce no warnings from our sources.
- Bundle IDs: saver `com.sarnau.MatrixRain`, host `com.sarnau.MatrixRainHost`, tests `com.sarnau.MatrixRainTests`.
- Log subsystem: `com.sarnau.MatrixRain`.
- No `fatalError`, no force-unwraps on Metal or CoreText objects. Setup failure → black screen, never a crash.
- All bundle resources are loaded via `Bundle(for: <our class>.self)`, never `Bundle.main`.
- Signing: ad hoc ("Sign to Run Locally", `CODE_SIGN_IDENTITY = "-"`). Personal use; no notarization.
- The Xcode project is generated: never hand-edit `MatrixRain.xcodeproj`; edit `project.yml` and run `xcodegen generate`. The `.xcodeproj` is git-ignored.
- Option ranges: speed 0.25–3.0 (default 1.0), density 0.5–2.0 (default 1.0), colour default sRGB `#00FF41`, bloom default on.

### Deviations from the spec (decided while planning)

- `Renderer` does not take the layer in `init`; it exposes `draw(in: CAMetalLayer, time:)` and `encodeFrame(into:target:time:)`. Keeps the renderer testable off-screen.
- Shader time wraps every **4096 s** (not 10 000 s) to keep float32 precision of the fall position well under one cell at speed 3.0 on 6K displays.
- The display link starts in `startAnimation()` only (the host app calls it explicitly); `viewDidMoveToWindow(nil)` still stops it.
- The `MatrixRainView` designated init gains a `defaults:` parameter so tests can inject a scratch `UserDefaults`.

## Review Focus

1. **The host never calls `stopAnimation`** (Sonoma+ `legacyScreenSaver` bug) → rendering must stop on the `com.apple.screensaver.willstop` notification or when the view leaves its window. Pinned by `MatrixRainViewTests.testWillStopHandlerStopsRendering` and `testRemovingFromWindowStopsRendering` (Task 5).
2. **Corrupt or non-finite stored settings** (a string under `speed`, NaN/∞ values) → load falls back to defaults or clamps; never NaN into the shader. Pinned by `SettingsTests.testNonFiniteValuesFallBackToDefaults` and `testWrongTypeFallsBackToDefault` (Task 2).
3. **Degenerate view sizes**: zero size before layout, NaN, or a width beyond the 16 384 px texture limit → no crash, nothing encoded for zero size. Pinned by `GridMetricsTests.testDegenerateSizes` (Task 1) and `RendererTests.testZeroSizeEncodesNothing` / `testOversizeResizeDoesNotCrash` (Task 4).
4. **Glyphs missing or clipped**: Hiragino lacks a glyph, or ink falls outside the 60 % sample window and gets cut off → every atlas cell has ink and almost none outside the window. Pinned by `GlyphAtlasTests.testEveryCellHasInkInsideSampleWindow` (Task 3).
5. **Long-running sessions**: near the time wrap, the rain must still render and still move. Pinned by `RendererTests.testRainStillMovesNearTimeWrap` (Task 4).

---

## File Map

| Path | Purpose | Task |
|---|---|---|
| `project.yml` | XcodeGen spec: 3 targets, schemes | 1 |
| `.gitignore` | Ignore generated project and build output | 1 |
| `Sources/MatrixRain/ShaderTypes.h` | `RainUniforms` C struct shared by Swift and MSL | 1 |
| `Sources/MatrixRain/MatrixRain-Bridging-Header.h` | Imports `ShaderTypes.h` into Swift | 1 |
| `Sources/MatrixRain/GridMetrics.swift` | Cell size / column / row maths | 1 |
| `Sources/Host/main.swift` | Host app entry point | 1 |
| `Sources/Host/AppDelegate.swift` | Host window + menu | 1, 5, 6 |
| `Sources/MatrixRain/Settings.swift` | Options value type + persistence | 2 |
| `Sources/MatrixRain/GlyphAtlas.swift` | CoreText → `MTLTexture` atlas | 3 |
| `Sources/MatrixRain/Shaders.metal` | Vertex + rain/downsample/composite fragments | 4 |
| `Sources/MatrixRain/Renderer.swift` | Metal pipelines and per-frame encoding | 4 |
| `Sources/MatrixRain/MatrixRainView.swift` | `ScreenSaverView` principal class | 5, 6 |
| `Sources/MatrixRain/ConfigureSheet.swift` | Options sheet controller | 6 |
| `Scripts/install.sh` | Release build + install into `~/Library/Screen Savers` | 7 |
| `README.md` | Build / install / debug notes | 7 |
| `Tests/MatrixRainTests/*.swift` | Unit tests | 1–6 |

Generated (not committed): `MatrixRain.xcodeproj`, `Support/MatrixRain-Info.plist`, `Support/Host-Info.plist`, `build/`.

## Common commands

Run from the repository root.

- Generate project: `xcodegen generate`
- Run tests (all or one class):
  `xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet`
  append e.g. `-only-testing:MatrixRainTests/GridMetricsTests` for one class.
- Build the saver: `xcodebuild build -project MatrixRain.xcodeproj -scheme MatrixRain -configuration Debug -derivedDataPath build/DerivedData -quiet`

---

### Task 1: Project scaffold + GridMetrics

**Files:**
- Create: `project.yml`, `.gitignore`, `Sources/MatrixRain/ShaderTypes.h`, `Sources/MatrixRain/MatrixRain-Bridging-Header.h`, `Sources/MatrixRain/GridMetrics.swift`, `Sources/Host/main.swift`, `Sources/Host/AppDelegate.swift`
- Test: `Tests/MatrixRainTests/GridMetricsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct GridMetrics: Equatable` with `init(pixelSize: CGSize, backingScale: CGFloat, density: Double, isPreview: Bool)` and `let cellWidth: Double`, `let cellHeight: Double` (pixels), `let columns: Int`, `let rows: Int`; statics `baseCellHeightPoints = 22.0`, `previewScale = 0.35`, `cellAspect = 0.6`, `minimumCellHeightPixels = 4.0`.
  - C struct `RainUniforms` (see header below), visible to Swift via the bridging header.
  - `AppDelegate` with `window: NSWindow?`, `appMenu: NSMenu?`, `static var isRunningTests: Bool`.
  - Targets `MatrixRain` (saver), `MatrixRainHost` (app, compiles `Sources/MatrixRain` + `Sources/Host`), `MatrixRainTests` (hosted by `MatrixRainHost`, `@testable import MatrixRainHost`).

- [ ] **Step 1: Write `project.yml`**

```yaml
name: MatrixRain
options:
  bundleIdPrefix: com.sarnau
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "-"
    DEVELOPMENT_TEAM: ""
    SWIFT_OBJC_BRIDGING_HEADER: Sources/MatrixRain/MatrixRain-Bridging-Header.h
    CLANG_ENABLE_MODULES: YES
targets:
  MatrixRain:
    type: bundle
    platform: macOS
    sources:
      - path: Sources/MatrixRain
    info:
      path: Support/MatrixRain-Info.plist
      properties:
        NSPrincipalClass: MatrixRainView
        CFBundleDisplayName: Matrix Rain
        CFBundleName: Matrix Rain
        CFBundleShortVersionString: "1.0"
        CFBundleVersion: "1"
    settings:
      base:
        PRODUCT_NAME: MatrixRain
        PRODUCT_BUNDLE_IDENTIFIER: com.sarnau.MatrixRain
        WRAPPER_EXTENSION: saver
        SKIP_INSTALL: YES
    scheme: {}
  MatrixRainHost:
    type: application
    platform: macOS
    sources:
      - path: Sources/MatrixRain
      - path: Sources/Host
    info:
      path: Support/Host-Info.plist
      properties:
        CFBundleDisplayName: Matrix Rain Host
        CFBundleShortVersionString: "1.0"
        CFBundleVersion: "1"
        NSPrincipalClass: NSApplication
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.sarnau.MatrixRainHost
    scheme:
      testTargets:
        - MatrixRainTests
  MatrixRainTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests/MatrixRainTests
    dependencies:
      - target: MatrixRainHost
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.sarnau.MatrixRainTests
        GENERATE_INFOPLIST_FILE: YES
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
MatrixRain.xcodeproj/
Support/
build/
DerivedData/
.DS_Store
xcuserdata/
```

- [ ] **Step 3: Write `Sources/MatrixRain/ShaderTypes.h`**

```c
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

/// Per-frame constants for every fragment shader. Shared by Swift and MSL so the layout cannot drift.
/// 64 bytes, 16-byte aligned.
typedef struct {
    simd_float4 color;       // rain colour, linear RGB (w unused)
    simd_float2 resolution;  // drawable size, pixels
    simd_float2 cellSize;    // grid cell size, pixels
    simd_float2 grid;        // columns, rows
    simd_float2 atlasGrid;   // glyph atlas columns, rows
    float time;              // seconds since start, wrapped
    float speed;             // fall speed multiplier
    float glyphCount;        // glyphs in the atlas
    float bloomIntensity;    // 0 disables bloom
} RainUniforms;

#endif
```

- [ ] **Step 4: Write `Sources/MatrixRain/MatrixRain-Bridging-Header.h`**

```c
#include "ShaderTypes.h"
```

- [ ] **Step 5: Write the host app shell**

`Sources/Host/main.swift`:

```swift
import AppKit

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.run()
```

`Sources/Host/AppDelegate.swift`:

```swift
import AppKit

/// Development host: shows the screensaver view in an ordinary window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var window: NSWindow?
    private(set) var appMenu: NSMenu?

    /// Unit tests are hosted by this app; don't open a window under them.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        guard !Self.isRunningTests else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Matrix Rain"
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Matrix Rain Host",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
        self.appMenu = appMenu
    }
}
```

- [ ] **Step 6: Write the failing test** `Tests/MatrixRainTests/GridMetricsTests.swift`

```swift
import XCTest
@testable import MatrixRainHost

final class GridMetricsTests: XCTestCase {
    func testRetinaDefaultDensity() {
        let m = GridMetrics(pixelSize: CGSize(width: 3024, height: 1964), backingScale: 2, density: 1, isPreview: false)
        XCTAssertEqual(m.cellHeight, 44, accuracy: 1e-9)
        XCTAssertEqual(m.cellWidth, 26.4, accuracy: 1e-9)
        XCTAssertEqual(m.columns, 115)   // 3024 / 26.4 = 114.5 → 115
        XCTAssertEqual(m.rows, 45)       // 1964 / 44 = 44.6 → 45
    }

    func testHigherDensityMeansSmallerCells() {
        let m = GridMetrics(pixelSize: CGSize(width: 1920, height: 1080), backingScale: 1, density: 2, isPreview: false)
        XCTAssertEqual(m.cellHeight, 11, accuracy: 1e-9)
        XCTAssertEqual(m.columns, 291)   // 1920 / 6.6 = 290.9
        XCTAssertEqual(m.rows, 99)       // 1080 / 11 = 98.2
    }

    func testPreviewUsesSmallerCells() {
        let m = GridMetrics(pixelSize: CGSize(width: 600, height: 376), backingScale: 2, density: 1, isPreview: true)
        XCTAssertEqual(m.cellHeight, 15.4, accuracy: 1e-9)  // 22 × 0.35 × 2
        XCTAssertEqual(m.columns, 65)
        XCTAssertEqual(m.rows, 25)
    }

    func testCellHeightNeverBelowMinimum() {
        let m = GridMetrics(pixelSize: CGSize(width: 100, height: 100), backingScale: 1, density: 1000, isPreview: true)
        XCTAssertEqual(m.cellHeight, GridMetrics.minimumCellHeightPixels)
    }

    func testDegenerateSizes() {
        let zero = GridMetrics(pixelSize: .zero, backingScale: 2, density: 1, isPreview: false)
        XCTAssertEqual(zero.columns, 1)
        XCTAssertEqual(zero.rows, 1)

        let nan = GridMetrics(pixelSize: CGSize(width: CGFloat.nan, height: -50), backingScale: .nan, density: .nan, isPreview: false)
        XCTAssertEqual(nan.columns, 1)
        XCTAssertEqual(nan.rows, 1)
        XCTAssertEqual(nan.cellHeight, 22, accuracy: 1e-9)   // scale and density fall back to 1
    }
}
```

- [ ] **Step 7: Generate the project and run the test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet -only-testing:MatrixRainTests/GridMetricsTests`
Expected: build FAILS with `cannot find 'GridMetrics' in scope`.

- [ ] **Step 8: Implement `Sources/MatrixRain/GridMetrics.swift`**

```swift
import CoreGraphics

/// Pure grid maths: how large one rain cell is in pixels and how many cells cover the drawable.
struct GridMetrics: Equatable {
    static let baseCellHeightPoints = 22.0
    static let previewScale = 0.35
    static let cellAspect = 0.6
    static let minimumCellHeightPixels = 4.0

    let cellWidth: Double
    let cellHeight: Double
    let columns: Int
    let rows: Int

    init(pixelSize: CGSize, backingScale: CGFloat, density: Double, isPreview: Bool) {
        let scale = backingScale.isFinite && backingScale > 0 ? Double(backingScale) : 1
        let density = density.isFinite && density > 0 ? density : 1
        let points = Self.baseCellHeightPoints * (isPreview ? Self.previewScale : 1) / density
        cellHeight = max(points * scale, Self.minimumCellHeightPixels)
        cellWidth = cellHeight * Self.cellAspect
        columns = Self.count(Double(pixelSize.width), cellWidth)
        rows = Self.count(Double(pixelSize.height), cellHeight)
    }

    private static func count(_ length: Double, _ cell: Double) -> Int {
        guard length.isFinite, length > 0 else { return 1 }
        return max(1, Int((length / cell).rounded(.up)))
    }
}
```

- [ ] **Step 9: Run the test to verify it passes**

Run: the command from Step 7 (without `xcodegen generate`).
Expected: `** TEST SUCCEEDED **`, 5 tests pass.

- [ ] **Step 10: Verify the saver target builds**

Run: `xcodebuild build -project MatrixRain.xcodeproj -scheme MatrixRain -configuration Debug -derivedDataPath build/DerivedData -quiet`
Expected: `** BUILD SUCCEEDED **` and `build/DerivedData/Build/Products/Debug/MatrixRain.saver` exists.

- [ ] **Step 11: Commit**

```bash
git add project.yml .gitignore Sources Tests
git commit -m "Scaffold XcodeGen project, host app, and GridMetrics"
```

---

### Task 2: Settings

**Files:**
- Create: `Sources/MatrixRain/Settings.swift`
- Test: `Tests/MatrixRainTests/SettingsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct Settings: Equatable` with `var speed: Double`, `var density: Double`, `var color: Settings.RGB`, `var bloom: Bool`.
  - `struct Settings.RGB: Equatable { var red, green, blue: Double }` — sRGB components in 0…1.
  - `init(speed: Double = 1.0, density: Double = 1.0, color: RGB = Settings.defaultColor, bloom: Bool = true)` — clamps to ranges; non-finite values fall back to defaults.
  - Statics: `speedRange`, `densityRange`, `defaultSpeed`, `defaultDensity`, `defaultColor`, `defaultBloom`.
  - `static func load(from defaults: UserDefaults) -> Settings`, `func save(to defaults: UserDefaults)`.
  - `var linearColor: SIMD3<Float>` — sRGB → linear.
  - `enum Settings.Keys` with `speed = "speed"`, `density = "density"`, `colorRed/Green/Blue = "colorRed"/"colorGreen"/"colorBlue"`, `bloom = "bloom"`.

- [ ] **Step 1: Write the failing test** `Tests/MatrixRainTests/SettingsTests.swift`

```swift
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
        XCTAssertEqual(s.density, 1.0)
        XCTAssertEqual(s.color, Settings.RGB(red: 0, green: 1, blue: 0x41 / 255))
        XCTAssertTrue(s.bloom)
    }

    func testRoundTrip() {
        let original = Settings(speed: 2.5, density: 0.75, color: .init(red: 0.2, green: 0.4, blue: 0.9), bloom: false)
        original.save(to: defaults)
        XCTAssertEqual(Settings.load(from: defaults), original)
    }

    func testOutOfRangeValuesAreClamped() {
        let s = Settings(speed: 10, density: 0.1, color: .init(red: -1, green: 2, blue: 0.5))
        XCTAssertEqual(s.speed, 3.0)
        XCTAssertEqual(s.density, 0.5)
        XCTAssertEqual(s.color, .init(red: 0, green: 1, blue: 0.5))

        defaults.set(0.01, forKey: Settings.Keys.speed)
        defaults.set(99.0, forKey: Settings.Keys.density)
        let loaded = Settings.load(from: defaults)
        XCTAssertEqual(loaded.speed, 0.25)
        XCTAssertEqual(loaded.density, 2.0)
    }

    func testNonFiniteValuesFallBackToDefaults() {
        let s = Settings(speed: .nan, density: .infinity, color: .init(red: .nan, green: 0.5, blue: -.infinity))
        XCTAssertEqual(s.speed, Settings.defaultSpeed)
        XCTAssertEqual(s.density, Settings.defaultDensity)
        XCTAssertEqual(s.color.red, Settings.defaultColor.red)
        XCTAssertEqual(s.color.green, 0.5)
        XCTAssertEqual(s.color.blue, Settings.defaultColor.blue)
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet -only-testing:MatrixRainTests/SettingsTests`
Expected: build FAILS with `cannot find 'Settings' in scope`.

- [ ] **Step 3: Implement `Sources/MatrixRain/Settings.swift`**

(`xcodegen generate` is needed after adding any new file so it joins the targets.)

```swift
import Foundation

/// User-adjustable options, persisted in the screensaver's defaults domain.
/// Every initialiser path clamps to the allowed ranges, so the renderer never sees invalid values.
struct Settings: Equatable {
    /// sRGB colour, each component 0…1.
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double
    }

    enum Keys {
        static let speed = "speed"
        static let density = "density"
        static let colorRed = "colorRed"
        static let colorGreen = "colorGreen"
        static let colorBlue = "colorBlue"
        static let bloom = "bloom"
    }

    static let speedRange: ClosedRange<Double> = 0.25...3.0
    static let densityRange: ClosedRange<Double> = 0.5...2.0
    static let defaultSpeed = 1.0
    static let defaultDensity = 1.0
    static let defaultColor = RGB(red: 0, green: 1, blue: 0x41 / 255)   // #00FF41
    static let defaultBloom = true

    var speed: Double
    var density: Double
    var color: RGB
    var bloom: Bool

    init(speed: Double = Settings.defaultSpeed,
         density: Double = Settings.defaultDensity,
         color: RGB = Settings.defaultColor,
         bloom: Bool = Settings.defaultBloom) {
        self.speed = Self.sanitize(speed, in: Self.speedRange, fallback: Self.defaultSpeed)
        self.density = Self.sanitize(density, in: Self.densityRange, fallback: Self.defaultDensity)
        self.color = RGB(
            red: Self.sanitize(color.red, in: 0...1, fallback: Self.defaultColor.red),
            green: Self.sanitize(color.green, in: 0...1, fallback: Self.defaultColor.green),
            blue: Self.sanitize(color.blue, in: 0...1, fallback: Self.defaultColor.blue)
        )
        self.bloom = bloom
    }

    static func load(from defaults: UserDefaults) -> Settings {
        func number(_ key: String) -> NSNumber? { defaults.object(forKey: key) as? NSNumber }
        func double(_ key: String, _ fallback: Double) -> Double { number(key)?.doubleValue ?? fallback }
        return Settings(
            speed: double(Keys.speed, defaultSpeed),
            density: double(Keys.density, defaultDensity),
            color: RGB(red: double(Keys.colorRed, defaultColor.red),
                       green: double(Keys.colorGreen, defaultColor.green),
                       blue: double(Keys.colorBlue, defaultColor.blue)),
            bloom: number(Keys.bloom)?.boolValue ?? defaultBloom
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(speed, forKey: Keys.speed)
        defaults.set(density, forKey: Keys.density)
        defaults.set(color.red, forKey: Keys.colorRed)
        defaults.set(color.green, forKey: Keys.colorGreen)
        defaults.set(color.blue, forKey: Keys.colorBlue)
        defaults.set(bloom, forKey: Keys.bloom)
        defaults.synchronize()   // ScreenSaverDefaults in legacyScreenSaver still needs this
    }

    /// The rain colour in linear RGB, as the shaders expect.
    var linearColor: SIMD3<Float> {
        func linear(_ c: Double) -> Float {
            Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
        }
        return SIMD3(linear(color.red), linear(color.green), linear(color.blue))
    }

    private static func sanitize(_ value: Double, in range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodegen generate && xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet -only-testing:MatrixRainTests/SettingsTests`
Expected: `** TEST SUCCEEDED **`, 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MatrixRain/Settings.swift Tests/MatrixRainTests/SettingsTests.swift
git commit -m "Add Settings with clamping and UserDefaults persistence"
```

---

### Task 3: GlyphAtlas

**Files:**
- Create: `Sources/MatrixRain/GlyphAtlas.swift`
- Test: `Tests/MatrixRainTests/GlyphAtlasTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `final class GlyphAtlas` with `init?(device: any MTLDevice, commandQueue: any MTLCommandQueue)`, `let texture: any MTLTexture` (512×576 `r8Unorm`, mipmapped), `let usedFallbackFont: Bool`.
  - Statics: `columns = 8`, `rows = 9`, `cellPixels = 64`, `glyphCount = 72`, `width = 512`, `height = 576`, `sampleWindow: ClosedRange<Double> = 0.2...0.8` (horizontal fraction of each cell the shader samples), `primaryFontName = "HiraginoSans-W3"`, `fallbackFontName = "Menlo-Regular"`, `primaryCharacters: [Character]`, `fallbackCharacters: [Character]`.
  - `struct GlyphAtlas.Bitmap { let pixels: [UInt8]; let usedFallback: Bool }` — row 0 is the top of the atlas.
  - `static func rasterize() -> Bitmap?`, `static func font(named: String) -> CTFont?`, `static func render(_ characters: [Character], font: CTFont) -> [UInt8]?`.

- [ ] **Step 1: Write the failing test** `Tests/MatrixRainTests/GlyphAtlasTests.swift`

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet -only-testing:MatrixRainTests/GlyphAtlasTests`
Expected: build FAILS with `cannot find 'GlyphAtlas' in scope`.

- [ ] **Step 3: Implement `Sources/MatrixRain/GlyphAtlas.swift`**

```swift
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodegen generate && xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet -only-testing:MatrixRainTests/GlyphAtlasTests`
Expected: `** TEST SUCCEEDED **`, 4 tests pass. If `testEveryCellHasInkInsideSampleWindow` reports spill, lower `fontSize` by 2 and re-run; do not loosen the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/MatrixRain/GlyphAtlas.swift Tests/MatrixRainTests/GlyphAtlasTests.swift
git commit -m "Add CoreText glyph atlas with mirrored katakana"
```

---

### Task 4: Shaders + Renderer

**Files:**
- Create: `Sources/MatrixRain/Shaders.metal`, `Sources/MatrixRain/Renderer.swift`
- Test: `Tests/MatrixRainTests/RendererTests.swift`

**Interfaces:**
- Consumes: `GridMetrics(pixelSize:backingScale:density:isPreview:)` (Task 1), `RainUniforms` (Task 1), `Settings`, `Settings.linearColor` (Task 2), `GlyphAtlas(device:commandQueue:)`, `GlyphAtlas.texture/columns/rows/glyphCount` (Task 3).
- Produces:
  - `@MainActor final class Renderer` with `init?(device: any MTLDevice, bundle: Bundle, settings: Settings, isPreview: Bool)`.
  - `let device: any MTLDevice`, `let commandQueue: any MTLCommandQueue`, `private(set) var settings: Settings`, `private(set) var metrics: GridMetrics`.
  - `func resize(pixelSize: CGSize, backingScale: CGFloat)`, `func update(settings: Settings)`.
  - `@discardableResult func encodeFrame(into commandBuffer: any MTLCommandBuffer, target: any MTLTexture, time: Float) -> Bool` — false when nothing can be drawn (zero size).
  - `func draw(in layer: CAMetalLayer, time: Float)`.
  - Statics: `outputPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb`, `maxTextureDimension = 16384`, `uniformsStride: Int`.
  - Shader function names: `fullscreenVertex`, `rainFragment`, `downsampleFragment`, `compositeFragment`.

- [ ] **Step 1: Write the failing test** `Tests/MatrixRainTests/RendererTests.swift`

```swift
import XCTest
import Metal
@testable import MatrixRainHost

@MainActor
final class RendererTests: XCTestCase {
    private let width = 640
    private let height = 400

    func testUniformsLayoutIs64Bytes() {
        XCTAssertEqual(Renderer.uniformsStride, 64)
    }

    func testFrameIsGreenAndNotEmpty() throws {
        let pixels = try render(makeRenderer(), time: 5)
        assertLooksLikeRain(pixels)
    }

    func testBloomOffStillRenders() throws {
        let pixels = try render(makeRenderer(bloom: false), time: 5)
        assertLooksLikeRain(pixels)
    }

    func testFramesChangeOverTime() throws {
        let renderer = try makeRenderer()
        XCTAssertNotEqual(try render(renderer, time: 5), try render(renderer, time: 6))
    }

    func testRainStillMovesNearTimeWrap() throws {
        let renderer = try makeRenderer()
        let a = try render(renderer, time: 4090)
        let b = try render(renderer, time: 4090.5)
        assertLooksLikeRain(a)
        XCTAssertNotEqual(a, b)
    }

    func testZeroSizeEncodesNothing() throws {
        let renderer = try makeRenderer()
        renderer.resize(pixelSize: .zero, backingScale: 2)
        let target = try makeTarget(device: renderer.device, width: 1, height: 1)
        let commandBuffer = try XCTUnwrap(renderer.commandQueue.makeCommandBuffer())
        XCTAssertFalse(renderer.encodeFrame(into: commandBuffer, target: target, time: 1))
        commandBuffer.commit()
    }

    func testOversizeResizeDoesNotCrash() throws {
        let renderer = try makeRenderer()
        renderer.resize(pixelSize: CGSize(width: 40_000, height: CGFloat.nan), backingScale: 2)
        renderer.resize(pixelSize: CGSize(width: 20_000, height: 100), backingScale: 2)
        XCTAssertGreaterThan(renderer.metrics.columns, 0)
        renderer.resize(pixelSize: CGSize(width: width, height: height), backingScale: 1)
        assertLooksLikeRain(try render(renderer, time: 5))
    }

    func testUpdateSettingsChangesGrid() throws {
        let renderer = try makeRenderer()
        let before = renderer.metrics.columns
        renderer.update(settings: Settings(density: 2))
        XCTAssertGreaterThan(renderer.metrics.columns, before)
        XCTAssertEqual(renderer.settings.density, 2)
    }

    // MARK: Helpers

    private func makeRenderer(bloom: Bool = true) throws -> Renderer {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try XCTUnwrap(Renderer(device: device, bundle: Bundle(for: Renderer.self),
                                              settings: Settings(bloom: bloom), isPreview: false))
        renderer.resize(pixelSize: CGSize(width: width, height: height), backingScale: 1)
        return renderer
    }

    private func makeTarget(device: any MTLDevice, width: Int, height: Int) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.outputPixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .private
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    /// Renders one frame and returns its BGRA bytes.
    private func render(_ renderer: Renderer, time: Float) throws -> [UInt8] {
        let target = try makeTarget(device: renderer.device, width: width, height: height)
        let bytesPerRow = width * 4
        let buffer = try XCTUnwrap(renderer.device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared))
        let commandBuffer = try XCTUnwrap(renderer.commandQueue.makeCommandBuffer())
        XCTAssertTrue(renderer.encodeFrame(into: commandBuffer, target: target, time: time))
        let blit = try XCTUnwrap(commandBuffer.makeBlitCommandEncoder())
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * height)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertNil(commandBuffer.error)
        return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self),
                                         count: bytesPerRow * height))
    }

    /// At least 1 % of pixels clearly lit, and green dominates red and blue overall.
    private func assertLooksLikeRain(_ bgra: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        var lit = 0, red = 0, green = 0, blue = 0
        for i in stride(from: 0, to: bgra.count, by: 4) {
            blue += Int(bgra[i]); green += Int(bgra[i + 1]); red += Int(bgra[i + 2])
            if bgra[i + 1] > 40 { lit += 1 }
        }
        XCTAssertGreaterThan(lit, bgra.count / 4 / 100, "too few lit pixels", file: file, line: line)
        XCTAssertGreaterThan(green, red * 2, "green should dominate red", file: file, line: line)
        XCTAssertGreaterThan(green, blue * 2, "green should dominate blue", file: file, line: line)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet -only-testing:MatrixRainTests/RendererTests`
Expected: build FAILS with `cannot find 'Renderer' in scope`.

- [ ] **Step 3: Write `Sources/MatrixRain/Shaders.metal`**

```metal
#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// MARK: Tuning

constant float kFallRate    = 0.4;   // screen heights per second at speed 1, column speed 1
constant float kHeadBoost   = 1.8;   // head brightness (> 1 so bloom picks it up)
constant float kHeadWhite   = 0.7;   // how far the head colour is pushed toward white
constant float kBackground  = 0.03;  // faint residual glyphs between drops
constant float kAtlasCell   = 64.0;  // GlyphAtlas.cellPixels
constant float kExposure    = 1.6;

// MARK: Helpers

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;   // 0…1, origin top-left
};

// PCG hash (Jarzynski & Olano 2020): integer-only, so no precision loss for large inputs.
static uint pcg(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

static uint hash2(uint a, uint b) { return pcg(a ^ pcg(b)); }

/// Uniform float in [0, 1).
static float unit(uint h) { return float(h >> 8) * (1.0 / 16777216.0); }

/// One raindrop in column `col`. Returns (brightness, cells behind the head); (0, -1) outside its trail.
static float2 drop(uint col, float row, float rows, float fall, uint salt) {
    float colSpeed = mix(0.6, 1.4, unit(hash2(col, salt)));
    float phase    = unit(hash2(col, salt + 1u));
    float len      = mix(0.3, 0.9, unit(hash2(col, salt + 2u)));   // trail length, screen heights
    float gap      = mix(0.2, 1.2, unit(hash2(col, salt + 3u)));   // dark pause after the trail
    float cycle    = 1.0 + len + gap;                              // distance the head travels per drop
    float headPos  = fract(fall * colSpeed / cycle + phase) * cycle;
    float behind   = floor(headPos * rows) - row;                  // whole cells: the head steps cell by cell
    float trail    = len * rows;
    if (behind < 0.0 || behind >= trail) {
        return float2(0.0, -1.0);
    }
    float b = 1.0 - behind / trail;
    return float2(b * b, behind);
}

// MARK: Shaders

vertex FullscreenOut fullscreenVertex(uint vid [[vertex_id]]) {
    // One oversized triangle covering the viewport: (0,0), (2,0), (0,2) in p-space.
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    FullscreenOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}

fragment float4 rainFragment(FullscreenOut in [[stage_in]],
                             constant RainUniforms &u [[buffer(0)]],
                             texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);

    float2 cellF = in.position.xy / u.cellSize;
    float2 cell = floor(cellF);
    float2 local = cellF - cell;
    uint col = uint(cell.x);
    float row = cell.y;
    float fall = u.time * u.speed * kFallRate;

    // Two independent drops per column; the brighter one wins.
    float2 a = drop(col, row, u.grid.y, fall, 0u);
    float2 b = drop(col, row, u.grid.y, fall, 7919u);
    float2 d = a.x >= b.x ? a : b;
    float brightness = d.x;
    float behind = d.y;

    // Glyphs mutate in place at a per-cell rate, faster just behind the head.
    uint cellId = col * 65537u + uint(row);
    float rate = mix(0.5, 3.0, unit(pcg(cellId)));
    if (behind >= 0.0 && behind < 4.0) {
        rate *= 3.0;
    }
    uint glyph = hash2(cellId, uint(floor(u.time * rate))) % uint(u.glyphCount);

    float3 color = u.color.rgb;
    if (brightness <= 0.0) {
        brightness = kBackground * unit(hash2(cellId, uint(floor(u.time * 0.5)) + 17u));
    } else if (behind == 0.0) {
        color = mix(color, float3(1.0), kHeadWhite);
        brightness = kHeadBoost;
    }

    // Sample the central 60 % of the square atlas cell so the glyph keeps its aspect ratio.
    uint atlasColumns = uint(u.atlasGrid.x);
    float2 atlasCell = float2(float(glyph % atlasColumns), float(glyph / atlasColumns));
    float2 inCell = float2(0.2 + 0.6 * local.x, local.y);
    float2 uv = (atlasCell + inCell) / u.atlasGrid;
    // Explicit LOD: derivatives jump at cell edges and would pick the wrong mip there.
    float lod = max(0.0, log2(kAtlasCell / u.cellSize.y));
    float ink = atlas.sample(s, uv, level(lod)).r;

    return float4(color * brightness * ink, 1.0);
}

fragment float4 downsampleFragment(FullscreenOut in [[stage_in]],
                                   texture2d<float> source [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 texel = 1.0 / float2(source.get_width(), source.get_height());
    // Four bilinear taps cover the 4 × 4 source block under each destination pixel.
    float3 c = source.sample(s, in.uv + texel * float2(-1.0, -1.0)).rgb
             + source.sample(s, in.uv + texel * float2( 1.0, -1.0)).rgb
             + source.sample(s, in.uv + texel * float2(-1.0,  1.0)).rgb
             + source.sample(s, in.uv + texel * float2( 1.0,  1.0)).rgb;
    return float4(c * 0.25, 1.0);
}

fragment float4 compositeFragment(FullscreenOut in [[stage_in]],
                                  constant RainUniforms &u [[buffer(0)]],
                                  texture2d<float> base [[texture(0)]],
                                  texture2d<float> bloom [[texture(1)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float3 c = base.sample(s, in.uv).rgb + bloom.sample(s, in.uv).rgb * u.bloomIntensity;
    c = 1.0 - exp(-c * kExposure);   // soft shoulder: bright heads go white instead of clipping
    return float4(c, 1.0);
}
```

- [ ] **Step 4: Write `Sources/MatrixRain/Renderer.swift`**

```swift
import Metal
import MetalPerformanceShaders
import QuartzCore
import os

private let logger = Logger(subsystem: "com.sarnau.MatrixRain", category: "Renderer")

/// Owns all Metal state and encodes one frame: rain → (bloom) → composite.
@MainActor
final class Renderer {
    static let outputPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
    static let intermediatePixelFormat: MTLPixelFormat = .rgba16Float
    static let maxTextureDimension = 16_384
    static let bloomIntensity: Float = 0.8
    static let bloomSigma: Float = 6
    static var uniformsStride: Int { MemoryLayout<RainUniforms>.stride }

    let device: any MTLDevice
    let commandQueue: any MTLCommandQueue
    private(set) var settings: Settings
    private(set) var metrics: GridMetrics

    private let rainPipeline: any MTLRenderPipelineState
    private let downsamplePipeline: any MTLRenderPipelineState
    private let compositePipeline: any MTLRenderPipelineState
    private let atlas: GlyphAtlas
    private let blur: MPSImageGaussianBlur
    private let isPreview: Bool

    private var pixelSize = CGSize.zero
    private var backingScale: CGFloat = 1
    private var baseTexture: (any MTLTexture)?
    private var bloomTextures: (small: any MTLTexture, blurred: any MTLTexture)?

    init?(device: any MTLDevice, bundle: Bundle, settings: Settings, isPreview: Bool) {
        guard let queue = device.makeCommandQueue() else {
            logger.error("Could not create command queue")
            return nil
        }
        guard MPSSupportsMTLDevice(device) else {
            logger.error("MetalPerformanceShaders unsupported on \(device.name, privacy: .public)")
            return nil
        }
        guard let atlas = GlyphAtlas(device: device, commandQueue: queue) else { return nil }
        do {
            let library = try device.makeDefaultLibrary(bundle: bundle)
            rainPipeline = try Self.makePipeline(device, library, "rainFragment", Self.intermediatePixelFormat)
            downsamplePipeline = try Self.makePipeline(device, library, "downsampleFragment", Self.intermediatePixelFormat)
            compositePipeline = try Self.makePipeline(device, library, "compositeFragment", Self.outputPixelFormat)
        } catch {
            logger.error("Pipeline setup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let blur = MPSImageGaussianBlur(device: device, sigma: Self.bloomSigma)
        blur.edgeMode = .clamp

        self.device = device
        self.commandQueue = queue
        self.atlas = atlas
        self.blur = blur
        self.settings = settings
        self.isPreview = isPreview
        self.metrics = GridMetrics(pixelSize: .zero, backingScale: 1, density: settings.density, isPreview: isPreview)
    }

    func resize(pixelSize requested: CGSize, backingScale: CGFloat) {
        let width = Self.clampDimension(requested.width)
        let height = Self.clampDimension(requested.height)
        let size = CGSize(width: width, height: height)
        guard size != pixelSize || backingScale != self.backingScale || baseTexture == nil else { return }
        pixelSize = size
        self.backingScale = backingScale
        updateMetrics()

        guard width > 0, height > 0 else {
            baseTexture = nil
            bloomTextures = nil
            return
        }
        baseTexture = makeIntermediate(width: width, height: height)
        let bloomWidth = max(1, width / 4), bloomHeight = max(1, height / 4)
        if let small = makeIntermediate(width: bloomWidth, height: bloomHeight),
           let blurred = makeIntermediate(width: bloomWidth, height: bloomHeight) {
            bloomTextures = (small, blurred)
        } else {
            bloomTextures = nil
        }
    }

    func update(settings: Settings) {
        self.settings = settings
        updateMetrics()
    }

    /// Encodes one frame into `target` (pixel format `outputPixelFormat`).
    /// Returns false, encoding nothing, while the drawable has zero size.
    @discardableResult
    func encodeFrame(into commandBuffer: any MTLCommandBuffer, target: any MTLTexture, time: Float) -> Bool {
        guard let base = baseTexture else { return false }
        var uniforms = makeUniforms(time: time)

        guard fullscreenPass(commandBuffer, target: base, pipeline: rainPipeline,
                             textures: [atlas.texture], uniforms: &uniforms) else { return false }

        var bloomSource: any MTLTexture = base
        if settings.bloom, let bloom = bloomTextures {
            guard fullscreenPass(commandBuffer, target: bloom.small, pipeline: downsamplePipeline,
                                 textures: [base], uniforms: &uniforms) else { return false }
            blur.encode(commandBuffer: commandBuffer, sourceTexture: bloom.small, destinationTexture: bloom.blurred)
            bloomSource = bloom.blurred
        } else {
            uniforms.bloomIntensity = 0
        }

        return fullscreenPass(commandBuffer, target: target, pipeline: compositePipeline,
                              textures: [base, bloomSource], uniforms: &uniforms)
    }

    /// Renders and presents one frame into the layer's next drawable. Skips the frame on any failure.
    func draw(in layer: CAMetalLayer, time: Float) {
        guard baseTexture != nil,
              let drawable = layer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        if encodeFrame(into: commandBuffer, target: drawable.texture, time: time) {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }

    // MARK: Private

    private func updateMetrics() {
        metrics = GridMetrics(pixelSize: pixelSize, backingScale: backingScale,
                              density: settings.density, isPreview: isPreview)
    }

    private func makeUniforms(time: Float) -> RainUniforms {
        let color = settings.linearColor
        var u = RainUniforms()
        u.color = SIMD4(color.x, color.y, color.z, 1)
        u.resolution = SIMD2(Float(pixelSize.width), Float(pixelSize.height))
        u.cellSize = SIMD2(Float(metrics.cellWidth), Float(metrics.cellHeight))
        u.grid = SIMD2(Float(metrics.columns), Float(metrics.rows))
        u.atlasGrid = SIMD2(Float(GlyphAtlas.columns), Float(GlyphAtlas.rows))
        u.time = time
        u.speed = Float(settings.speed)
        u.glyphCount = Float(GlyphAtlas.glyphCount)
        u.bloomIntensity = settings.bloom ? Self.bloomIntensity : 0
        return u
    }

    private func fullscreenPass(_ commandBuffer: any MTLCommandBuffer, target: any MTLTexture,
                                pipeline: any MTLRenderPipelineState, textures: [any MTLTexture],
                                uniforms: inout RainUniforms) -> Bool {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: Self.uniformsStride, index: 0)
        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    private func makeIntermediate(width: Int, height: Int) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.intermediatePixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private static func clampDimension(_ value: CGFloat) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return min(Int(value), maxTextureDimension)
    }

    private static func makePipeline(_ device: any MTLDevice, _ library: any MTLLibrary,
                                     _ fragment: String, _ format: MTLPixelFormat) throws -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = fragment
        descriptor.vertexFunction = library.makeFunction(name: "fullscreenVertex")
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = format
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodegen generate && xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet -only-testing:MatrixRainTests/RendererTests`
Expected: `** TEST SUCCEEDED **`, 8 tests pass.

- [ ] **Step 6: Visually spot-check one frame**

Add (temporarily, do not commit) a line to `testFrameIsGreenAndNotEmpty` that writes the bytes as a PNG to `$TMPDIR/matrix-frame.png` using `CGImage` + `CGImageDestination`, run it, open the PNG, and confirm: columns of mirrored katakana, bright whitish heads, fading green trails, soft glow. Remove the line afterwards.

- [ ] **Step 7: Run the whole suite**

Run: `xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Sources/MatrixRain/Shaders.metal Sources/MatrixRain/Renderer.swift Tests/MatrixRainTests/RendererTests.swift
git commit -m "Add procedural rain shader, bloom, and Metal renderer"
```

---

### Task 5: MatrixRainView + host window

**Files:**
- Create: `Sources/MatrixRain/MatrixRainView.swift`
- Modify: `Sources/Host/AppDelegate.swift` (`applicationDidFinishLaunching`)
- Test: `Tests/MatrixRainTests/MatrixRainViewTests.swift`

**Interfaces:**
- Consumes: `Renderer(device:bundle:settings:isPreview:)`, `Renderer.resize(pixelSize:backingScale:)`, `Renderer.draw(in:time:)`, `Renderer.outputPixelFormat`, `Renderer.update(settings:)` (Task 4); `Settings.load(from:)`, `Settings.save(to:)` (Task 2).
- Produces:
  - `@objc(MatrixRainView) final class MatrixRainView: ScreenSaverView`.
  - `init?(frame: NSRect, isPreview: Bool, defaults: UserDefaults)` (designated) and `override convenience init?(frame: NSRect, isPreview: Bool)` (uses `ScreenSaverDefaults` for the bundle ID).
  - `var isRendering: Bool`, `var hasRenderer: Bool`, `var currentSettings: Settings`, `var rendererMetrics: GridMetrics?`, `func handleWillStop()`, `func apply(_ settings: Settings)`.
  - `static let timeWrap: CFTimeInterval = 4096`.

- [ ] **Step 1: Write the failing test** `Tests/MatrixRainTests/MatrixRainViewTests.swift`

```swift
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

    func testWillStopHandlerStopsRendering() throws {
        let view = try makeView()
        view.startAnimation()
        view.handleWillStop()
        XCTAssertFalse(view.isRendering)
        view.handleWillStop()   // second notification is harmless
        XCTAssertFalse(view.isRendering)
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
        Settings(density: 1.5).save(to: defaults)
        let view = try XCTUnwrap(MatrixRainView(frame: .zero, isPreview: false, defaults: defaults))
        XCTAssertEqual(view.currentSettings.density, 1.5)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet -only-testing:MatrixRainTests/MatrixRainViewTests`
Expected: build FAILS with `cannot find 'MatrixRainView' in scope`.

- [ ] **Step 3: Implement `Sources/MatrixRain/MatrixRainView.swift`**

```swift
import Metal
import QuartzCore
import ScreenSaver
import os

private let logger = Logger(subsystem: "com.sarnau.MatrixRain", category: "View")

/// The screensaver's principal class. Frames are driven by the view's display link rather than
/// `animateOneFrame`, so every display renders at its own refresh rate.
///
/// Since Sonoma, legacyScreenSaver often never calls `stopAnimation` and keeps old instances alive,
/// so rendering also stops on the `com.apple.screensaver.willstop` notification and when the view
/// leaves its window. All stop paths are idempotent.
@objc(MatrixRainView)
final class MatrixRainView: ScreenSaverView {
    static let timeWrap: CFTimeInterval = 4096
    private static let willStopNotification = Notification.Name("com.apple.screensaver.willstop")

    private let metalLayer = CAMetalLayer()
    private let defaults: UserDefaults
    private var settings: Settings
    private var renderer: Renderer?
    private var displayLink: CADisplayLink?
    private var stopObserver: (any NSObjectProtocol)?
    private var startTime: CFTimeInterval = 0

    var isRendering: Bool { displayLink != nil }
    var hasRenderer: Bool { renderer != nil }
    var currentSettings: Settings { settings }
    var rendererMetrics: GridMetrics? { renderer?.metrics }

    init?(frame: NSRect, isPreview: Bool, defaults: UserDefaults) {
        self.defaults = defaults
        self.settings = Settings.load(from: defaults)
        super.init(frame: frame, isPreview: isPreview)
        setUpRendering()
    }

    override convenience init?(frame: NSRect, isPreview: Bool) {
        self.init(frame: frame, isPreview: isPreview, defaults: Self.makeDefaults())
    }

    required init?(coder: NSCoder) {
        let defaults = Self.makeDefaults()
        self.defaults = defaults
        self.settings = Settings.load(from: defaults)
        super.init(coder: coder)
        setUpRendering()
    }

    private static func makeDefaults() -> UserDefaults {
        let identifier = Bundle(for: MatrixRainView.self).bundleIdentifier ?? "com.sarnau.MatrixRain"
        return ScreenSaverDefaults(forModuleWithName: identifier) ?? .standard
    }

    private func setUpRendering() {
        animationTimeInterval = 1   // ScreenSaverView's own timer is unused; keep it idle
        metalLayer.pixelFormat = Renderer.outputPixelFormat
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        wantsLayer = true

        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.error("No Metal device; showing black screen")
            return
        }
        metalLayer.device = device
        renderer = Renderer(device: device, bundle: Bundle(for: MatrixRainView.self),
                            settings: settings, isPreview: isPreview)
        if renderer == nil {
            logger.error("Renderer setup failed; showing black screen")
        }
        updateDrawableSize()
    }

    // MARK: Layer

    override func makeBackingLayer() -> CALayer { metalLayer }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}          // content comes from the display link
    override func animateOneFrame() {}

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopRendering()
        } else {
            updateDrawableSize()
        }
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let pixels = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        metalLayer.contentsScale = scale
        if pixels.width >= 1, pixels.height >= 1 {
            metalLayer.drawableSize = pixels
        }
        renderer?.resize(pixelSize: pixels, backingScale: scale)
    }

    // MARK: Animation

    override func startAnimation() {
        super.startAnimation()
        startRendering()
    }

    override func stopAnimation() {
        super.stopAnimation()
        stopRendering()
    }

    /// Called for `com.apple.screensaver.willstop`; internal so tests can drive it directly.
    func handleWillStop() {
        stopRendering()
    }

    private func startRendering() {
        guard renderer != nil, displayLink == nil else { return }
        updateDrawableSize()
        startTime = CACurrentMediaTime()
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        stopObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.willStopNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWillStop() }
        }
    }

    private func stopRendering() {
        displayLink?.invalidate()
        displayLink = nil
        if let observer = stopObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            stopObserver = nil
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        let elapsed = (link.targetTimestamp - startTime).truncatingRemainder(dividingBy: Self.timeWrap)
        renderer?.draw(in: metalLayer, time: Float(elapsed))
    }

    // MARK: Settings

    func apply(_ newSettings: Settings) {
        settings = newSettings
        newSettings.save(to: defaults)
        renderer?.update(settings: newSettings)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodegen generate && xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet -only-testing:MatrixRainTests/MatrixRainViewTests`
Expected: `** TEST SUCCEEDED **`, 7 tests pass.

- [ ] **Step 5: Show the view in the host window**

In `Sources/Host/AppDelegate.swift`, add a stored property and extend `applicationDidFinishLaunching` after `window.center()`:

```swift
    private(set) var rainView: MatrixRainView?
```

```swift
        if let view = MatrixRainView(frame: window.contentLayoutRect, isPreview: false) {
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            view.startAnimation()
            rainView = view
        }
```

- [ ] **Step 6: Run the host app and look at it**

Run: `xcodebuild build -project MatrixRain.xcodeproj -scheme MatrixRainHost -configuration Debug -derivedDataPath build/DerivedData -quiet && open build/DerivedData/Build/Products/Debug/MatrixRainHost.app`
Expected: a window with animated rain — mirrored katakana, white-ish heads, fading trails, glyphs flickering, glow around bright glyphs. Resize the window: rain refills with no stretching. Quit with ⌘Q.

- [ ] **Step 7: Verify the saver builds and commit**

Run: `xcodebuild build -project MatrixRain.xcodeproj -scheme MatrixRain -configuration Debug -derivedDataPath build/DerivedData -quiet`
Expected: `** BUILD SUCCEEDED **`.

```bash
git add Sources/MatrixRain/MatrixRainView.swift Sources/Host/AppDelegate.swift Tests/MatrixRainTests/MatrixRainViewTests.swift
git commit -m "Add MatrixRainView screensaver class with display-link rendering"
```

---

### Task 6: Options sheet

**Files:**
- Create: `Sources/MatrixRain/ConfigureSheet.swift`
- Modify: `Sources/MatrixRain/MatrixRainView.swift` (add configure sheet section), `Sources/Host/AppDelegate.swift` (Options… menu item)
- Test: `Tests/MatrixRainTests/ConfigureSheetTests.swift`

**Interfaces:**
- Consumes: `Settings` and its statics (Task 2); `MatrixRainView.apply(_:)`, `MatrixRainView.currentSettings` (Task 5); `AppDelegate.appMenu`, `AppDelegate.window`, `AppDelegate.rainView` (Tasks 1, 5).
- Produces:
  - `@MainActor final class ConfigureSheetController: NSObject` with `init(onSave: @escaping (Settings) -> Void)`, `let window: NSWindow`, `let speedSlider: NSSlider`, `let densitySlider: NSSlider`, `let colorWell: NSColorWell`, `let bloomCheckbox: NSButton`, `func load(_ settings: Settings)`, `var editedSettings: Settings`, `func present(settings: Settings) -> NSWindow`, `@objc func ok(_ sender: Any?)`, `@objc func cancel(_ sender: Any?)`.
  - On `MatrixRainView`: `lazy var configureController: ConfigureSheetController`, `override var hasConfigureSheet: Bool` (true), `override var configureSheet: NSWindow?`.

- [ ] **Step 1: Write the failing test** `Tests/MatrixRainTests/ConfigureSheetTests.swift`

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet -only-testing:MatrixRainTests/ConfigureSheetTests`
Expected: build FAILS with `cannot find 'ConfigureSheetController' in scope`.

- [ ] **Step 3: Implement `Sources/MatrixRain/ConfigureSheet.swift`**

```swift
import AppKit

/// The "Options…" sheet, built in code. Edits stay in the controls until OK; Cancel discards them.
@MainActor
final class ConfigureSheetController: NSObject {
    let window: NSWindow
    let speedSlider: NSSlider
    let densitySlider: NSSlider
    let colorWell: NSColorWell
    let bloomCheckbox: NSButton
    private let onSave: (Settings) -> Void

    init(onSave: @escaping (Settings) -> Void) {
        self.onSave = onSave
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                          styleMask: [.titled], backing: .buffered, defer: true)
        speedSlider = NSSlider(value: Settings.defaultSpeed,
                               minValue: Settings.speedRange.lowerBound,
                               maxValue: Settings.speedRange.upperBound,
                               target: nil, action: nil)
        densitySlider = NSSlider(value: Settings.defaultDensity,
                                 minValue: Settings.densityRange.lowerBound,
                                 maxValue: Settings.densityRange.upperBound,
                                 target: nil, action: nil)
        colorWell = NSColorWell()
        bloomCheckbox = NSButton(checkboxWithTitle: "Glow (bloom)", target: nil, action: nil)
        super.init()
        buildLayout()
    }

    func present(settings: Settings) -> NSWindow {
        load(settings)
        return window
    }

    func load(_ settings: Settings) {
        speedSlider.doubleValue = settings.speed
        densitySlider.doubleValue = settings.density
        colorWell.color = NSColor(srgbRed: settings.color.red, green: settings.color.green,
                                  blue: settings.color.blue, alpha: 1)
        bloomCheckbox.state = settings.bloom ? .on : .off
    }

    var editedSettings: Settings {
        let fallback = Settings.defaultColor
        let color = colorWell.color.usingColorSpace(.sRGB)
        return Settings(
            speed: speedSlider.doubleValue,
            density: densitySlider.doubleValue,
            color: Settings.RGB(red: color.map { Double($0.redComponent) } ?? fallback.red,
                                green: color.map { Double($0.greenComponent) } ?? fallback.green,
                                blue: color.map { Double($0.blueComponent) } ?? fallback.blue),
            bloom: bloomCheckbox.state == .on
        )
    }

    @objc func ok(_ sender: Any?) {
        onSave(editedSettings)
        close()
    }

    @objc func cancel(_ sender: Any?) {
        close()
    }

    private func close() {
        colorWell.deactivate()
        if NSColorPanel.sharedColorPanelExists {
            NSColorPanel.shared.orderOut(nil)
        }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }

    private func buildLayout() {
        let okButton = NSButton(title: "OK", target: self, action: #selector(ok(_:)))
        okButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Fall speed:"), speedSlider],
            [NSTextField(labelWithString: "Density:"), densitySlider],
            [NSTextField(labelWithString: "Color:"), colorWell],
            [NSGridCell.emptyContentView, bloomCheckbox],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        speedSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        densitySlider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let buttons = NSStackView(views: [cancelButton, okButton])
        buttons.spacing = 12

        let stack = NSStackView(views: [grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
    }
}
```

- [ ] **Step 4: Hook the sheet into `MatrixRainView`**

Append inside the `// MARK: Settings` section of `Sources/MatrixRain/MatrixRainView.swift`:

```swift
    lazy var configureController = ConfigureSheetController { [weak self] in self?.apply($0) }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        configureController.present(settings: settings)
    }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodegen generate && xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet -only-testing:MatrixRainTests/ConfigureSheetTests`
Expected: `** TEST SUCCEEDED **`, 5 tests pass.

- [ ] **Step 6: Add "Options…" to the host app menu**

In `Sources/Host/AppDelegate.swift`, in `buildMainMenu()` insert before the Quit item:

```swift
        let options = NSMenuItem(title: "Options…", action: #selector(showOptions(_:)), keyEquivalent: ",")
        options.target = self
        appMenu.addItem(options)
        appMenu.addItem(.separator())
```

and add the action to `AppDelegate`:

```swift
    @objc private func showOptions(_ sender: Any?) {
        guard let window, let sheet = rainView?.configureSheet else { return }
        window.beginSheet(sheet)
    }
```

- [ ] **Step 7: Try the sheet in the host app**

Run: `xcodebuild build -project MatrixRain.xcodeproj -scheme MatrixRainHost -configuration Debug -derivedDataPath build/DerivedData -quiet && open build/DerivedData/Build/Products/Debug/MatrixRainHost.app`
Expected: ⌘, opens the sheet. Changing colour to red + OK turns the rain red immediately; density 2 + OK gives smaller glyphs; unticking Glow + OK removes the halo; Cancel after edits leaves the rain unchanged. Settings persist across relaunch.

- [ ] **Step 8: Run the whole suite and commit**

Run: `xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet`
Expected: `** TEST SUCCEEDED **` (35 tests).

```bash
git add Sources/MatrixRain/ConfigureSheet.swift Sources/MatrixRain/MatrixRainView.swift Sources/Host/AppDelegate.swift Tests/MatrixRainTests/ConfigureSheetTests.swift
git commit -m "Add options sheet for speed, density, colour, and bloom"
```

---

### Task 7: Install script, README, release verification

**Files:**
- Create: `Scripts/install.sh`, `README.md`

**Interfaces:**
- Consumes: the `MatrixRain` scheme (Task 1) and everything built so far.
- Produces: `Scripts/install.sh` (no arguments) that installs `~/Library/Screen Savers/MatrixRain.saver`.

- [ ] **Step 1: Write `Scripts/install.sh`**

```bash
#!/bin/bash
# Builds MatrixRain.saver (Release, universal) and installs it for the current user.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild build -project MatrixRain.xcodeproj -scheme MatrixRain -configuration Release \
    -derivedDataPath build/DerivedData -quiet

SAVER="build/DerivedData/Build/Products/Release/MatrixRain.saver"
DEST="$HOME/Library/Screen Savers"
mkdir -p "$DEST"
rm -rf "$DEST/MatrixRain.saver"
cp -R "$SAVER" "$DEST/"

# legacyScreenSaver caches loaded bundles; restart it so the new build is picked up.
killall legacyScreenSaver 2>/dev/null || true

echo "Installed $DEST/MatrixRain.saver ($(lipo -archs "$DEST/MatrixRain.saver/Contents/MacOS/MatrixRain"))"
```

Then: `chmod +x Scripts/install.sh`

- [ ] **Step 2: Write `README.md`**

````markdown
# Matrix Rain

A macOS 14+ screensaver that renders film-style Matrix digital rain with Metal.

## Build and install

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
Scripts/install.sh
```

Then pick **Matrix Rain** in System Settings → Screen Saver. **Options…** sets fall speed, density, colour, and glow.

## Develop

```bash
xcodegen generate
open MatrixRain.xcodeproj
```

- Run the **MatrixRainHost** scheme to see the effect in a window (⌘, opens the options sheet). Use it for the Metal frame debugger.
- Tests: `xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS'`
- Logs: `log stream --predicate 'subsystem == "com.sarnau.MatrixRain"'`

The project file is generated from `project.yml`; edit that, not the `.xcodeproj`.

Design: `docs/superpowers/specs/2026-10-06-matrix-screensaver-design.md`.
````

- [ ] **Step 3: Check for warnings in a clean build**

Run: `rm -rf build && xcodegen generate && xcodebuild build -project MatrixRain.xcodeproj -scheme MatrixRain -configuration Release -derivedDataPath build/DerivedData 2>&1 | grep -E "warning:" | grep -v "^ld:" || echo "no warnings"`
Expected: `no warnings`. Fix any warning from our sources before continuing.

- [ ] **Step 4: Install and verify universal binary**

Run: `Scripts/install.sh`
Expected: final line `Installed …/MatrixRain.saver (x86_64 arm64)`.

- [ ] **Step 5: Manual verification in System Settings** (ask the user to confirm each item)

1. System Settings → Screen Saver shows **Matrix Rain**, and its thumbnail animates.
2. **Options…** opens the sheet; changes persist after closing and reopening System Settings.
3. **Preview** (or hot corner) runs full-screen on every attached display, each filled edge to edge.
4. After dismissing the screensaver, Activity Monitor → GPU History / `legacyScreenSaver` CPU% drops to ~0 within a few seconds. (`log stream --predicate 'subsystem == "com.sarnau.MatrixRain"'` shows no errors.)

- [ ] **Step 6: Commit**

```bash
git add Scripts/install.sh README.md
git commit -m "Add install script and README"
```
