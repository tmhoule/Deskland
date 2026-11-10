import Foundation
import WebKit

/// Resolves only files contained in the resource root, including after symlink resolution.
struct ResourceURLResolver {
    private let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    func resolve(_ url: URL?) throws -> URL {
        guard let url = url, url.scheme == "deskland", url.host == "app" else {
            throw URLError(.unsupportedURL)
        }
        // Decode exactly once, including encoded separators, before checking containment.
        guard let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              let path = encodedPath.removingPercentEncoding, !path.utf8.contains(0) else {
            throw URLError(.noPermissionsToReadFile)
        }
        let file = try canonicalFile(root.appendingPathComponent(path))
        let prefix = root.path == "/" ? "/" : root.path + "/"
        guard file.path != root.path, file.path.hasPrefix(prefix) else {
            throw URLError(.noPermissionsToReadFile)
        }
        return file
    }

    private func canonicalFile(_ url: URL) throws -> URL {
        // Foundation may leave aliases unresolved when the final file does not exist.
        // Resolve the nearest existing ancestor, then append only the missing suffix.
        var ancestor = url.standardizedFileURL
        var suffix: [String] = []
        let fm = FileManager.default
        while !fm.fileExists(atPath: ancestor.path) {
            // Do not append a dangling symlink as if it were an ordinary missing file.
            guard (try? fm.destinationOfSymbolicLink(atPath: ancestor.path)) == nil,
                  ancestor.path != "/" else {
                throw URLError(.noPermissionsToReadFile)
            }
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var file = ancestor.resolvingSymlinksInPath()
        for component in suffix.reversed() {
            file.appendPathComponent(component)
        }
        return file
    }
}

/// Bundle-only resources, with no localhost server and no arbitrary file access.
final class ResourceScheme: NSObject, WKURLSchemeHandler {
    private let resolver: ResourceURLResolver

    init(root: URL) { resolver = ResourceURLResolver(root: root) }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            let file = try resolver.resolve(urlSchemeTask.request.url)
            // A successful resolution guarantees a non-nil request URL.
            guard let url = urlSchemeTask.request.url else { throw URLError(.unsupportedURL) }
            let data = try Data(contentsOf: file)
            let types = ["html": "text/html", "js": "application/javascript", "json": "application/json",
                         "png": "image/png", "webp": "image/webp", "css": "text/css"]
            let mime = types[file.pathExtension] ?? "application/octet-stream"
            let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count,
                                       textEncodingName: mime.hasPrefix("text/") || mime == "application/javascript" ? "utf-8" : nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
