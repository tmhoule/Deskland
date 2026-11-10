import CoreGraphics

/// AX uses global top-left logical coordinates. Keep the shared Windows wire
/// format out of this conversion; the injected bridge converts points to the
/// receiving wallpaper view's backing scale immediately before delivery.
enum DesktopGeometry {
    static func localRectangles(_ rectangles: [CGRect], displayBounds: CGRect) -> [[Double]] {
        rectangles.compactMap { rectangle in
            guard !rectangle.isNull, !rectangle.isInfinite,
                  rectangle.width > 0, rectangle.height > 0,
                  rectangle.intersects(displayBounds) else { return nil }
            let local = rectangle.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
            return [Double(local.minX), Double(local.minY), Double(local.maxX), Double(local.maxY)]
        }
    }
}
