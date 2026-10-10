import CoreGraphics

/// Pure grid maths: how large one rain cell is in pixels and how many cells cover the drawable.
struct GridMetrics: Equatable {
    static let defaultGlyphSizePoints = 22.0
    static let previewScale = 0.35
    static let cellAspect = 0.6
    static let minimumCellHeightPixels = 4.0

    let cellWidth: Double
    let cellHeight: Double
    let columns: Int
    let rows: Int

    /// `glyphSize` is the cell height in points; the preview thumbnail scales it down.
    init(pixelSize: CGSize, backingScale: CGFloat, glyphSize: Double, isPreview: Bool) {
        let scale = backingScale.isFinite && backingScale > 0 ? Double(backingScale) : 1
        let glyphSize = glyphSize.isFinite && glyphSize > 0 ? glyphSize : Self.defaultGlyphSizePoints
        let points = glyphSize * (isPreview ? Self.previewScale : 1)
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
