import WebKit

/// Whitelist of URL schemes the render WebView may navigate to.
/// Everything else (file://, http://, ftp://, nil) is cancelled — a template
/// must not reach the local filesystem or downgrade to cleartext.
enum NavigationPolicy {
    // `data:` is intentionally allowed: RSS/feed templates embed images as data: URIs (no
    // network round-trip per icon), and a data: URI cannot reach the filesystem or any host —
    // it decodes to bytes in-memory. Do not tighten this away, it will break image templates.
    private static let allowedSchemes: Set<String> = ["about", "https", TemplateAssetSchemeHandler.scheme, "data"]

    static func decide(for url: URL?) -> WKNavigationActionPolicy {
        guard let scheme = url?.scheme?.lowercased(), allowedSchemes.contains(scheme) else {
            return .cancel
        }
        return .allow
    }
}
