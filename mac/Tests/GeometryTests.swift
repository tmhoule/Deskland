import CoreGraphics

@main
struct GeometryTests {
    static func main() {
        let display = CGRect(x: -1440, y: 100, width: 1440, height: 900)
        let values = DesktopGeometry.localRectangles([
            CGRect(x: -1400.25, y: 130.5, width: 76.5, height: 100.25),
            CGRect(x: 100, y: 100, width: 80, height: 90),
            CGRect.zero,
            CGRect(x: -1450, y: 110, width: 40, height: 50)
        ], displayBounds: display)
        precondition(values.count == 2)
        precondition(values[0] == [39.75, 30.5, 116.25, 130.75], "Preserve fractional logical geometry")
        precondition(values[1] == [-10, 10, 30, 60], "Preserve bounds of partially visible icons")
        precondition(DesktopGeometry.localRectangles([], displayBounds: display).isEmpty)
        print("Geometry tests passed")
    }
}
