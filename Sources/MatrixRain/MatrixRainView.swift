import Metal
import QuartzCore
import ScreenSaver
import os

private let logger = Logger(subsystem: "com.sarnau.MatrixRain", category: "View")

/// The screensaver's principal class. Frames are driven by the view's display link rather than
/// `animateOneFrame`, so every display renders at its own refresh rate.
///
/// Rendering stops on `stopAnimation` and when the host removes the view from its window; both paths
/// are idempotent and free the size-dependent GPU textures, because legacyScreenSaver keeps stopped
/// instances alive. The global `com.apple.screensaver.willstop` notification is deliberately ignored:
/// it reaches every instance in the process, including the System Settings preview, which the host
/// never restarts.
@objc(MatrixRainView)
final class MatrixRainView: ScreenSaverView {
    static let timeWrap: CFTimeInterval = 4096

    private let metalLayer = CAMetalLayer()
    private let defaults: UserDefaults
    private var settings: Settings
    private var renderer: Renderer?
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    /// Set by `stopAnimation`, cleared by `startAnimation`: the host asked this view to stay still.
    private var stoppedByHost = false

    var isRendering: Bool { displayLink != nil }
    var hasRenderer: Bool { renderer != nil }
    var currentSettings: Settings { settings }
    var rendererMetrics: GridMetrics? { renderer?.metrics }
    var rendererHasSurfaces: Bool { renderer?.hasSurfaces ?? false }
    private(set) var timeOffset: CFTimeInterval = 0

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
        let metalView = MetalLayerView(metalLayer: metalLayer)
        metalView.frame = bounds
        metalView.autoresizingMask = [.width, .height]
        addSubview(metalView)

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

    override func animateOneFrame() {}

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
        startIfShown()
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
            startIfShown()
        }
    }

    /// legacyScreenSaver often loads a fresh instance into System Settings without ever calling
    /// `startAnimation`, which left the preview black; render whenever the view is actually shown.
    private func startIfShown() {
        guard window != nil, !stoppedByHost, bounds.width >= 1, bounds.height >= 1 else { return }
        startRendering()
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
        stoppedByHost = false
        startRendering()
    }

    override func stopAnimation() {
        super.stopAnimation()
        stoppedByHost = true
        stopRendering()
    }

    private func startRendering() {
        guard renderer != nil, displayLink == nil else { return }
        updateDrawableSize()
        startTime = CACurrentMediaTime()
        // The rain is a pure function of time, so a random start keeps displays and activations distinct.
        timeOffset = CFTimeInterval.random(in: 0..<Self.timeWrap)
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopRendering() {
        displayLink?.invalidate()
        displayLink = nil
        renderer?.releaseSurfaces()
    }

    @objc private func step(_ link: CADisplayLink) {
        let elapsed = (link.targetTimestamp - startTime + timeOffset).truncatingRemainder(dividingBy: Self.timeWrap)
        renderer?.draw(in: metalLayer, time: Float(elapsed))
    }

    // MARK: Settings

    lazy var configureController = ConfigureSheetController { [weak self] in self?.apply($0) }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        configureController.present(settings: settings)
    }

    func apply(_ newSettings: Settings) {
        settings = newSettings
        newSettings.save(to: defaults)
        renderer?.update(settings: newSettings)
    }
}

/// Hosts the CAMetalLayer in a child view. legacyScreenSaver hosts the ScreenSaverView's own layer in
/// System Settings and the screensaver window, so that layer must stay the one AppKit created.
private final class MetalLayerView: NSView {
    private let metalLayer: CAMetalLayer

    init(metalLayer: CAMetalLayer) {
        self.metalLayer = metalLayer
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer { metalLayer }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}          // content comes from the display link
}
