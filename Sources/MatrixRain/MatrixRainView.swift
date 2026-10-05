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
