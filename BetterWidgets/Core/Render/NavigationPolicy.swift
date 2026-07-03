import WebKit

/// Whitelist of URL schemes the render WebView may navigate to.
/// Everything else (file://, http://, ftp://, nil) is cancelled — a template
/// must not reach the local filesystem or downgrade to cleartext.
enum NavigationPolicy {
    private static let allowedSchemes: Set<String> = ["about", "https", "bwasset", "data"]

    static func decide(for url: URL?) -> WKNavigationActionPolicy {
        guard let scheme = url?.scheme?.lowercased(), allowedSchemes.contains(scheme) else {
            return .cancel
        }
        return .allow
    }
}
