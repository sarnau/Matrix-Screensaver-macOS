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
