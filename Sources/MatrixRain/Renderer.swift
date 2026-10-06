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
    static let bloomIntensity: Float = 0.6
    static let bloomSigma: Float = 3
    static var uniformsStride: Int { MemoryLayout<RainUniforms>.stride }

    let device: any MTLDevice
    let commandQueue: any MTLCommandQueue
    private(set) var settings: Settings
    private(set) var metrics: GridMetrics
    var hasSurfaces: Bool { baseTexture != nil }

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
        self.metrics = GridMetrics(pixelSize: .zero, backingScale: 1, glyphSize: settings.glyphSize, isPreview: isPreview)
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

    /// Frees the size-dependent textures. The next `resize` recreates them.
    /// legacyScreenSaver keeps stopped instances alive, so they must not hold full-screen textures.
    func releaseSurfaces() {
        baseTexture = nil
        bloomTextures = nil
        pixelSize = .zero
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
                              glyphSize: settings.glyphSize, isPreview: isPreview)
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
