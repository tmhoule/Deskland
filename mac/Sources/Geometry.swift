import CoreGraphics

/// AX uses global top-left logical coordinates. Keep the shared Windows wire
/// format out of this conversion; the injected bridge converts points to the
/// receiving wallpaper view's backing scale immediately before delivery.
enum DesktopGeometry {
    /// Assign each rect to a single display by its largest overlapping area, then return
    /// that display's rects offset into `bounds`' local space. A rect is never sent to two
    /// renderers: a partially spanning icon goes to the display covering most of it. Ties
    /// keep the earlier display, so the main display wins a centred span.
    static func localRectangles(_ rectangles: [CGRect], in displays: [CGRect], for bounds: CGRect) -> [[Double]] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        var result: [[Double]] = []
        for rectangle in rectangles {
            guard !rectangle.isNull, !rectangle.isInfinite,
                  rectangle.width > 0, rectangle.height > 0 else { continue }
            var bestIndex = -1
            var bestArea = CGFloat(0)
            for (index, display) in displays.enumerated() {
                let overlap = rectangle.intersection(display)
                guard overlap.width > 0, overlap.height > 0 else { continue }
                let area = overlap.width * overlap.height
                if area > bestArea { bestArea = area; bestIndex = index }
            }
            guard bestIndex >= 0 else { continue }
            guard displays[bestIndex] == bounds else { continue }
            let local = rectangle.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            result.append([Double(local.minX), Double(local.minY), Double(local.maxX), Double(local.maxY)])
        }
        return result
    }

    /// Single-display convenience: every rect intersecting `displayBounds`, offset to local.
    /// Retained for the Settings preview, which models the main display only.
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
