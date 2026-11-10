import AppKit
import ApplicationServices

struct FinderIconSnapshot {
    let status: String
    /// Accessibility global coordinates: logical points, origin at the main display's top left.
    let rectangles: [CGRect]
    /// Diagnostic categories only. Never contains an item's name, path, or AX attribute value.
    let detail: String
}

/// Call read() on a dedicated serial background queue, not the main queue.
/// No AX elements survive a read, so a Finder restart does not leave stale cached elements.
final class FinderIconProvider {
    func read() -> FinderIconSnapshot {
        guard AXIsProcessTrusted() else {
            return snapshot("permissionRequired", "accessibilityPermissionRequired")
        }
        guard let finder = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder" && !$0.isTerminated
        }) else {
            return snapshot("finderUnavailable", "finderNotRunning")
        }

        let application = AXUIElementCreateApplication(finder.processIdentifier)
        // Setting this on an application element bounds messaging for its process's elements.
        // The separate read deadline also bounds a large or changing accessibility tree.
        let timeoutError = AXUIElementSetMessagingTimeout(application, 0.10)
        guard timeoutError == .success else {
            return snapshot(timeoutError == .apiDisabled ? "permissionRequired" : "desktopUnavailable",
                            "configureTimeout.axError=\(timeoutError.rawValue)")
        }
        let traversal = Traversal()
        guard let desktop = traversal.findDesktop(application, depth: 0) else {
            return failure(traversal, fallback: "desktopMarkerNotFound")
        }
        traversal.stage = "desktop"
        guard let children = traversal.children(desktop, required: true) else {
            return failure(traversal, fallback: "desktopChildrenUnavailable")
        }
        var rectangles: [CGRect] = []
        for child in children {
            guard let result = traversal.collect(child, depth: 0) else {
                return failure(traversal, fallback: "desktopGeometryUnavailable")
            }
            rectangles.append(contentsOf: result.rectangles)
        }
        guard traversal.failure == nil else {
            return failure(traversal, fallback: "desktopTraversalIncomplete")
        }
        // A successfully identified desktop with zero children/items is valid, not an error.
        return FinderIconSnapshot(status: "ready", rectangles: rectangles,
                                  detail: traversal.diagnostic(rectangles.isEmpty ? "desktopEmpty" : "desktopGeometryRead"))
    }

    private func snapshot(_ status: String, _ detail: String) -> FinderIconSnapshot {
        FinderIconSnapshot(status: status, rectangles: [], detail: detail)
    }

    private func failure(_ traversal: Traversal, fallback: String) -> FinderIconSnapshot {
        if traversal.failure == .permission {
            return snapshot("permissionRequired", traversal.diagnostic("accessibilityPermissionRequired"))
        }
        return snapshot("desktopUnavailable", traversal.diagnostic(traversal.failure?.rawValue ?? fallback))
    }

    private final class Traversal {
        enum Failure: String {
            case permission = "accessibilityPermissionRequired"
            case messaging = "accessibilityMessagingFailed"
            case bounded = "desktopTraversalLimitReached"
            case geometry = "desktopGeometryUnavailable"
        }

        struct Geometry {
            var rectangles: [CGRect]
            var imageCount: Int
        }

        private let deadline = ProcessInfo.processInfo.systemUptime + 2.0
        private var operations = 0
        private var nodes = 0
        var failure: Failure?
        var stage = "discovery"
        private var fatalDiagnostic: String?
        private var optionalDiagnostics: [String] = []
        private var desktopMarker: String?

        func diagnostic(_ category: String) -> String {
            ([category] + [fatalDiagnostic, desktopMarker].compactMap { $0 } + optionalDiagnostics)
                .joined(separator: ";")
        }

        private func enter(depth: Int) -> Bool {
            nodes += 1
            guard failure == nil else { return false }
            guard depth <= 24, nodes <= 4096,
                  ProcessInfo.processInfo.systemUptime < deadline else {
                failure = .bounded
                return false
            }
            return true
        }

        private func attribute(_ element: AXUIElement, _ name: String, required: Bool = false) -> CFTypeRef? {
            guard failure == nil else { return nil }
            operations += 1
            guard operations <= 24000, ProcessInfo.processInfo.systemUptime < deadline else {
                failure = .bounded
                return nil
            }
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            switch error {
            case .success:
                return value
            default:
                // Only fixed stage/attribute names and numeric AX errors enter diagnostics.
                // Optional metadata often returns -25200/-25212 even on a valid element.
                // A failing unrelated Finder menu/window must not poison desktop discovery.
                let diagnostic = "\(stage).\(name).axError=\(error.rawValue)"
                if error == .apiDisabled || required {
                    failure = error == .apiDisabled ? .permission : .messaging
                    fatalDiagnostic = diagnostic
                } else if optionalDiagnostics.count < 4, !optionalDiagnostics.contains(diagnostic) {
                    optionalDiagnostics.append(diagnostic)
                }
            }
            return nil
        }

        private func string(_ element: AXUIElement, _ name: String, required: Bool = false) -> String? {
            attribute(element, name, required: required) as? String
        }

        func children(_ element: AXUIElement, required: Bool = false) -> [AXUIElement]? {
            guard let value = attribute(element, kAXChildrenAttribute, required: required) else { return nil }
            guard let elements = value as? [AXUIElement] else {
                if required {
                    failure = .geometry
                    fatalDiagnostic = "\(stage).AXChildren.invalidType"
                }
                return nil
            }
            return elements
        }

        func findDesktop(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            guard enter(depth: depth) else { return nil }
            let role = string(element, kAXRoleAttribute, required: depth == 0)
            // Do not traverse menus/toolbars or their optional accessibility metadata.
            // Finder's desktop is a root-level scroll area on some macOS releases.
            if [kAXMenuBarRole, kAXMenuRole, kAXToolbarRole].contains(role ?? "") { return nil }
            if role == kAXScrollAreaRole, isDesktop(element, allowDescription: depth == 1) {
                return failure == nil ? element : nil
            }
            // A scroll area's contents cannot identify a different desktop scroll area.
            // In particular, do not enumerate the file items in ordinary Finder windows.
            if role == kAXScrollAreaRole { return nil }
            guard let descendants = children(element, required: depth == 0) else { return nil }
            // Try direct scroll areas before ordinary window subtrees, independent of
            // Finder's child ordering. No file items in unmarked scroll areas are read.
            var scrollAreas: [AXUIElement] = []
            var otherChildren: [AXUIElement] = []
            for child in descendants {
                if string(child, kAXRoleAttribute) == kAXScrollAreaRole {
                    scrollAreas.append(child)
                } else {
                    otherChildren.append(child)
                }
            }
            for child in scrollAreas + otherChildren {
                if let desktop = findDesktop(child, depth: depth + 1) { return desktop }
                if failure != nil { return nil }
            }
            return nil
        }

        private func isDesktop(_ element: AXUIElement, allowDescription: Bool) -> Bool {
            if string(element, kAXSubroleAttribute) == "AXDesktop" {
                desktopMarker = "marker=desktopSubrole"
                return true
            }
            if let identifier = string(element, "AXIdentifier"), desktopIdentifier(identifier) {
                desktopMarker = "marker=desktopIdentifier"
                return true
            }
            // Last-resort exact semantic marker ONLY on an application-root scroll area,
            // never a scroll area inside an ordinary Finder window. A read-only local
            // probe found root AXScrollArea -> AXGroup -> AXImage leaves with no subrole
            // or identifier. Never inspect ordinary windows' descriptions for folder names.
            // This fallback is not translated: localized/changed trees lacking all known
            // markers fail closed rather than guessing by screen geometry or child roles.
            guard allowDescription else { return false }
            let matches = string(element, kAXDescriptionAttribute)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "desktop"
            if matches { desktopMarker = "marker=rootDesktopDescription" }
            return matches
        }

        private func desktopIdentifier(_ identifier: String) -> Bool {
            // Accept a standalone desktop token, including AXDesktop and camelCase IDs,
            // not arbitrary strings containing "desktop" (e.g. a desktop-folder browser).
            let separated = identifier.replacingOccurrences(
                of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            let tokens = separated.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            let permitted: Set<String> = ["ax", "desktop", "view", "scroll", "area", "finder", "com", "apple"]
            return tokens.contains("desktop") && tokens.allSatisfy { permitted.contains(String($0)) }
        }

        private func frame(_ element: AXUIElement, required: Bool = true) -> CGRect? {
            guard let position = attribute(element, kAXPositionAttribute, required: required),
                  CFGetTypeID(position) == AXValueGetTypeID(),
                  let size = attribute(element, kAXSizeAttribute, required: required),
                  CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
            let positionValue = unsafeBitCast(position, to: AXValue.self)
            let sizeValue = unsafeBitCast(size, to: AXValue.self)
            guard AXValueGetType(positionValue) == .cgPoint,
                  AXValueGetType(sizeValue) == .cgSize else { return nil }
            var point = CGPoint.zero
            var dimensions = CGSize.zero
            guard AXValueGetValue(positionValue, .cgPoint, &point),
                  AXValueGetValue(sizeValue, .cgSize, &dimensions),
                  point.x.isFinite, point.y.isFinite,
                  dimensions.width.isFinite, dimensions.height.isFinite,
                  dimensions.width >= 0, dimensions.height >= 0 else { return nil }
            // Keep fractional logical coordinates and negative secondary-display origins.
            return CGRect(origin: point, size: dimensions)
        }

        func collect(_ element: AXUIElement, depth: Int) -> Geometry? {
            guard enter(depth: depth), let role = string(element, kAXRoleAttribute, required: true) else { return nil }
            // Never harvest nested windows or application trees, even if Finder changes
            // the desktop's children to reference other UI surfaces.
            if role == kAXWindowRole || role == kAXApplicationRole {
                return Geometry(rectangles: [], imageCount: 0)
            }
            if role == kAXImageRole || role == kAXStaticTextRole {
                guard let bounds = frame(element) else {
                    if failure == nil { failure = .geometry }
                    return nil
                }
                return Geometry(rectangles: bounds.isEmpty ? [] : [bounds],
                                imageCount: role == kAXImageRole ? 1 : 0)
            }
            var result = Geometry(rectangles: [], imageCount: 0)
            // Once inside the confirmed desktop, incomplete child enumeration must
            // invalidate the snapshot rather than silently dropping icon obstacles.
            guard let descendants = children(element, required: true) else { return nil }
            let emptyContainerRoles: Set<String> = [
                kAXGroupRole, kAXListRole, kAXScrollAreaRole, "AXLayoutArea", "AXOutline", "AXTable"
            ]
            if descendants.isEmpty, !emptyContainerRoles.contains(role) {
                // An unknown leaf might be a new Finder icon representation. Do not
                // report a misleading ready/empty result when its geometry is unknown.
                if failure == nil { failure = .geometry }
                return nil
            }
            for child in descendants {
                guard let nested = collect(child, depth: depth + 1) else { return nil }
                result.rectangles.append(contentsOf: nested.rectangles)
                result.imageCount += nested.imageCount
            }
            guard failure == nil else { return nil }
            if (role == kAXGroupRole || role == "AXCell" || role == "AXLayoutItem"),
               result.imageCount == 1, let first = result.rectangles.first {
                var union = result.rectangles.dropFirst().reduce(first) { $0.union($1) }
                if let groupBounds = frame(element, required: false), !groupBounds.isEmpty,
                   union.insetBy(dx: -64, dy: -64).contains(groupBounds) {
                    union = union.union(groupBounds)
                }
                guard failure == nil else { return nil }
                // Union the icon and its sibling labels at the smallest item group.
                // The proximity guard above excludes viewport-sized container frames.
                result.rectangles = [union]
            }
            // AX trees are not a stable Finder API. The locally observed desktop exposes
            // only 64x64 AXImage leaves, with no separate label geometry. Such snapshots
            // cover image bounds ONLY, not unexposed labels; do not invent label extents.
            // If icons/labels are ungrouped, return their separate bounds instead of
            // inventing name-based associations. If a
            // future Finder exposes no recognizable image/text roles, geometry is not
            // inferable here; this provider intentionally never reads titles, values,
            // URLs, filenames, or filesystem paths. It also cannot ensure atomicity if
            // the user moves icons during this bounded, best-effort snapshot.
            return result
        }
    }
}
