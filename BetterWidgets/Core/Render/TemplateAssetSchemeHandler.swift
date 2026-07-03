import WebKit
import UniformTypeIdentifiers

/// Resolves a bwasset://template/<path> request to a real file under templateDir.
/// Returns nil if the resolved path escapes templateDir (traversal) or doesn't exist.
func resolveTemplateAsset(templateDir: URL, requestPath: String) -> URL? {
    let root = templateDir.standardizedFileURL
    let trimmed = requestPath.hasPrefix("/") ? String(requestPath.dropFirst()) : requestPath
    let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
    guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
    guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
    return candidate
}

/// Serves template assets over a private bwasset:// scheme so the render WebView
/// never needs file:// access. Only files inside templateDir are reachable.
final class TemplateAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    private let templateDir: URL

    init(templateDir: URL) {
        self.templateDir = templateDir
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let fileURL = resolveTemplateAsset(templateDir: templateDir, requestPath: url.path),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

extension TemplateAssetSchemeHandler {
    /// Single source of truth for the confined scheme name — shared by NavigationPolicy's
    /// whitelist and RenderEngine's scheme registration/base URL so a rename can't silently
    /// desync the two.
    static let scheme = "bwasset"
}
