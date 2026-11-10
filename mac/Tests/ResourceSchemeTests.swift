import Foundation

@main
struct ResourceSchemeTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Expected test directory") }
        // Canonicalize the existing workspace, not individual possibly missing files.
        let workspace = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).resolvingSymlinksInPath()
        let fm = FileManager.default
        let root = workspace.appendingPathComponent("bundle", isDirectory: true)
        let sibling = workspace.appendingPathComponent("bundle-other", isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try fm.createDirectory(at: sibling, withIntermediateDirectories: true)
        let page = root.appendingPathComponent("nested/hello world.html")
        try Data("resource test".utf8).write(to: page)
        let outside = sibling.appendingPathComponent("secret.txt")
        try Data("outside".utf8).write(to: outside)
        try fm.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: sibling)
        try fm.createSymbolicLink(at: root.appendingPathComponent("outside.txt"), withDestinationURL: outside)
        try fm.createSymbolicLink(at: root.appendingPathComponent("dangling"), withDestinationURL: sibling.appendingPathComponent("missing"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("inside.html"), withDestinationURL: page)
        let alias = workspace.appendingPathComponent("bundle-alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: root)
        let resolver = ResourceURLResolver(root: root)
        var checks = 0

        func accepts(_ string: String, _ expected: URL, using candidate: ResourceURLResolver? = nil) throws {
            let result = try (candidate ?? resolver).resolve(URL(string: string))
            precondition(result.path == expected.path, "Unexpected path: \(string): \(result), expected \(expected.path)")
            checks += 1
        }
        func rejects(_ string: String?, _ code: URLError.Code) {
            do {
                _ = try resolver.resolve(string.flatMap(URL.init(string:)))
                fatalError("Accepted forbidden URL: \(string ?? "nil")")
            } catch let error as URLError {
                precondition(error.code == code, "Wrong error for \(string ?? "nil"): \(error)")
                checks += 1
            } catch { fatalError("Unexpected error: \(error)") }
        }

        try accepts("deskland://app/nested/hello%20world.html", page)
        try accepts("deskland://app/nested/hello%20world.html?version=2#fragment", page)
        try accepts("deskland://app/nested%2Fhello%20world.html", page)
        try accepts("deskland://app/inside.html", page)
        try accepts("deskland://app/inside.html", page, using: ResourceURLResolver(root: alias))
        try accepts("deskland://app/missing.png", root.appendingPathComponent("missing.png"))
        try accepts("deskland://app/missing.png", root.appendingPathComponent("missing.png"), using: ResourceURLResolver(root: alias))
        try accepts("deskland://app/missing/deeper/file.png", root.appendingPathComponent("missing/deeper/file.png"), using: ResourceURLResolver(root: alias))
        // Missing resources still resolve inside the bundle; loading reports file-not-found.
        let missing = try resolver.resolve(URL(string: "deskland://app/missing.png"))
        do {
            _ = try Data(contentsOf: missing)
            fatalError("Missing resource unexpectedly loaded")
        } catch {
            precondition((error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSFileReadNoSuchFileError)
            checks += 1
        }
        for path in ["../bundle-other/secret.txt", "%2e%2e/bundle-other/secret.txt",
                     "%2E%2E%2Fbundle-other%2Fsecret.txt", "nested/../../bundle-other/secret.txt",
                     "escape/secret.txt", "escape/missing/deeper.png", "outside.txt",
                     "dangling", "dangling/file.png", "", "/", "%00secret.txt"] {
            rejects("deskland://app/" + path, .noPermissionsToReadFile)
        }
        for url in ["https://app/nested/hello.html", "file:///etc/passwd", "deskland://other/file",
                    "deskland:///file", "deskland://app.evil/file"] {
            rejects(url, .unsupportedURL)
        }
        rejects(nil, .unsupportedURL)
        let contents = try Data(contentsOf: resolver.resolve(URL(string: "deskland://app/inside.html")))
        precondition(contents == Data("resource test".utf8))
        print("ResourceScheme: \(checks) checks passed")
    }
}
