import SwiftUI
import WebKit

/// A CodeMirror 5-backed code editor (syntax highlighting + line numbers) embedded in a
/// WKWebView, bridged to a SwiftUI `@Binding<String>`. Reuses the same `bwasset://` confinement
/// (`TemplateAssetSchemeHandler` + `NavigationPolicy`) as the render engine and live preview —
/// `editor.html` and the vendored CodeMirror assets are served from `assetsDir`, never `file://`.
///
/// Bridge direction JS -> Swift: CodeMirror's `change` event posts the full text to the
/// `bwEditor` script message handler, which writes it into `text.wrappedValue`.
/// Bridge direction Swift -> JS: `updateNSView` calls `window.bwSetContent(text, mode)`, guarded
/// by `lastSet` so an edit's own echo (SwiftUI re-rendering with the value the editor just sent)
/// doesn't bounce back into CodeMirror and reset its cursor/undo-history.
struct CodeEditorBridge: NSViewRepresentable {
    enum Language: String { case html, json }

    @Binding var text: String
    var language: Language
    let assetsDir: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "bwEditor")
        config.setURLSchemeHandler(TemplateAssetSchemeHandler(templateDir: assetsDir),
                                   forURLScheme: TemplateAssetSchemeHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.pendingText = text
        context.coordinator.pendingLanguage = language
        webView.load(URLRequest(url: URL(string: "\(TemplateAssetSchemeHandler.scheme)://template/editor.html")!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // The binding itself can point at a different `@Published` property after this (e.g. a
        // tab switch from index.html to manifest.json) — re-capture it every time, not just once
        // in makeCoordinator(), or the JS->Swift echo below would keep writing into whichever
        // property was active when the bridge was first created.
        context.coordinator.text = $text
        context.coordinator.applyExternal(text: text, language: language)
    }

    func makeCoordinator() -> Coordinator { Coordinator($text) }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        fileprivate var text: Binding<String>
        weak var webView: WKWebView?
        var pendingText = ""
        var pendingLanguage: Language = .html
        private var loaded = false
        private var lastSet = ""

        init(_ text: Binding<String>) { self.text = text }

        // Text edited in CodeMirror flows back to the SwiftUI binding. WKScriptMessageHandler
        // callbacks are always delivered on the main thread, so this writes synchronously on the
        // main actor at receipt — no `Task { @MainActor in ... }` hop, and therefore no window
        // for a tab switch (which re-points `self.text` in `updateNSView`) to land the edit in
        // the wrong tab's binding.
        nonisolated func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = message.body as? String else { return }
            MainActor.assumeIsolated {
                self.lastSet = value
                self.text.wrappedValue = value
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            setContent(pendingText, pendingLanguage)
        }

        nonisolated func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(NavigationPolicy.decide(for: action.request.url))
        }

        // Push external changes (tab switch / programmatic edit) into CodeMirror,
        // skipping echoes of what the editor itself just sent.
        func applyExternal(text value: String, language: Language) {
            pendingText = value; pendingLanguage = language
            guard loaded, value != lastSet else { return }
            setContent(value, language)
        }

        private func setContent(_ value: String, _ language: Language) {
            lastSet = value
            let escaped = String(data: try! JSONSerialization.data(withJSONObject: [value]), encoding: .utf8)!
            // escaped is a JSON array "[\"...\"]"; take element 0 in JS.
            webView?.evaluateJavaScript("window.bwSetContent(\(escaped)[0], '\(language.rawValue)');")
        }
    }
}
