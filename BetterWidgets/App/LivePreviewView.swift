import SwiftUI
import WebKit

/// A live WKWebView preview of a template — same `window.BW` contract and `bwasset://`
/// confinement (`TemplateAssetSchemeHandler` + `NavigationPolicy`) as the render engine
/// (`RenderEngine`), so what's shown here matches the final rendered widget.
///
/// Reload-over-reinject: the bundled templates read `window.BW` once at load and never
/// listen for a live-update event, so the only reliable way to reflect a context change
/// (params/size/theme/data) is a fresh `loadHTMLString` with a rebuilt `window.BW` user
/// script — that's what `updateNSView` does, guarded so an unchanged context doesn't
/// reload on every SwiftUI body re-evaluation. `Coordinator.reinject` still dispatches a
/// `bwParamsChanged` event as an offered hook for templates that want a flash-free
/// update, but nothing ships that relies on it yet.
struct LivePreviewView: NSViewRepresentable {
    let html: String
    let templateDir: URL
    let context: RenderContext

    func makeNSView(context ctx: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(TemplateAssetSchemeHandler(templateDir: templateDir),
                                   forURLScheme: TemplateAssetSchemeHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = ctx.coordinator
        ctx.coordinator.load(webView, html: html, context: self.context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context ctx: Context) {
        webView.appearance = NSAppearance(named: self.context.theme == .dark ? .darkAqua : .aqua)
        ctx.coordinator.reloadIfNeeded(webView, html: html, context: self.context)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loaded = false
        private var lastPayload: String?

        func load(_ webView: WKWebView, html: String, context: RenderContext) {
            inject(webView, context: context)
            webView.appearance = NSAppearance(named: context.theme == .dark ? .darkAqua : .aqua)
            webView.loadHTMLString(html, baseURL: URL(string: "\(TemplateAssetSchemeHandler.scheme)://template/"))
        }

        /// Rebuilds the `window.BW` user script and reloads, but only when the payload
        /// actually changed — SwiftUI calls `updateNSView` far more often than the preview
        /// context actually changes, and a WKWebView reload flashes.
        func reloadIfNeeded(_ webView: WKWebView, html: String, context: RenderContext) {
            guard let payload = try? context.bwJSON(), payload != lastPayload else { return }
            load(webView, html: html, context: context)
        }

        private func inject(_ webView: WKWebView, context: RenderContext) {
            let bw = (try? context.bwJSON()) ?? "{}"
            lastPayload = bw
            let controller = webView.configuration.userContentController
            controller.removeAllUserScripts()
            let script = "window.BW = \(bw); window.BW.ready = function(){};"
            controller.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        /// Re-push params/size/theme into a loaded page without a full reload — offered for
        /// templates that opt into listening for `bwParamsChanged`. Unused by the bundled
        /// templates today (see the reload-over-reinject note on the type).
        func reinject(_ webView: WKWebView, context: RenderContext) {
            guard loaded, let bw = try? context.bwJSON() else { return }
            webView.evaluateJavaScript(
                "window.BW = \(bw); window.dispatchEvent(new Event('bwParamsChanged'));", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }

        nonisolated func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(NavigationPolicy.decide(for: action.request.url))
        }
    }
}
