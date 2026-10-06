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
        static let glyphSize = "glyphSize"
        /// Pre-1.1 option: cell height was 22 pt divided by this.
        static let legacyDensity = "density"
        static let colorRed = "colorRed"
        static let colorGreen = "colorGreen"
        static let colorBlue = "colorBlue"
        static let bloom = "bloom"
    }

    static let speedRange: ClosedRange<Double> = 0.25...3.0
    static let glyphSizeRange: ClosedRange<Double> = 12...44   // points
    static let defaultSpeed = 1.0
    static let defaultGlyphSize = 22.0
    static let defaultColor = RGB(red: 0, green: 1, blue: 0x41 / 255)   // #00FF41
    static let defaultBloom = true

    var speed: Double
    var glyphSize: Double
    var color: RGB
    var bloom: Bool

    init(speed: Double = Settings.defaultSpeed,
         glyphSize: Double = Settings.defaultGlyphSize,
         color: RGB = Settings.defaultColor,
         bloom: Bool = Settings.defaultBloom) {
        self.speed = Self.sanitize(speed, in: Self.speedRange, fallback: Self.defaultSpeed)
        self.glyphSize = Self.sanitize(glyphSize, in: Self.glyphSizeRange, fallback: Self.defaultGlyphSize)
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
            glyphSize: number(Keys.glyphSize)?.doubleValue ?? legacyGlyphSize(defaults) ?? defaultGlyphSize,
            color: RGB(red: double(Keys.colorRed, defaultColor.red),
                       green: double(Keys.colorGreen, defaultColor.green),
                       blue: double(Keys.colorBlue, defaultColor.blue)),
            bloom: number(Keys.bloom)?.boolValue ?? defaultBloom
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(speed, forKey: Keys.speed)
        defaults.set(glyphSize, forKey: Keys.glyphSize)
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

    private static func legacyGlyphSize(_ defaults: UserDefaults) -> Double? {
        guard let density = (defaults.object(forKey: Keys.legacyDensity) as? NSNumber)?.doubleValue,
              density.isFinite, density > 0 else { return nil }
        return defaultGlyphSize / density
    }

    private static func sanitize(_ value: Double, in range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
