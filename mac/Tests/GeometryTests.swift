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
        multiDisplayTests()
        print("Geometry tests passed")
    }

    static func multiDisplayTests() {
        // Main display is the origin-anchored one; a secondary sits to the right.
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let secondary = CGRect(x: 1512, y: 0, width: 1440, height: 900)
        let displays = [main, secondary]
        let icons = [
            CGRect(x: 100, y: 100, width: 64, height: 64),     // fully in main
            CGRect(x: 1512, y: 100, width: 64, height: 64),    // fully in secondary
            CGRect(x: 1440, y: 100, width: 64, height: 64),    // spans edge, 72 in main vs 16 in secondary → main
            CGRect(x: 1500, y: 100, width: 64, height: 64),    // spans edge, 12 in main vs 62 in secondary → secondary
            CGRect(x: -200, y: 100, width: 64, height: 64),    // off all displays: dropped
        ]
        let onMain = DesktopGeometry.localRectangles(icons, in: displays, for: main)
        let onSecondary = DesktopGeometry.localRectangles(icons, in: displays, for: secondary)
        precondition(onMain.count == 2, "main gets the two rects majority-owned by main")
        precondition(onMain[0] == [100, 100, 164, 164], "main local origin")
        precondition(onMain[1] == [1440, 100, 1504, 164], "edge rect with main majority is local to main")
        precondition(onSecondary.count == 2, "secondary gets its two majority-owned rects")
        precondition(onSecondary[0] == [0, 100, 64, 164], "fully-secondary rect is offset to its local origin")
        precondition(onSecondary[1] == [-12, 100, 52, 164], "edge rect with secondary majority is local to secondary")
        precondition(DesktopGeometry.localRectangles(icons, in: displays, for: CGRect.zero).isEmpty)
    }
}
