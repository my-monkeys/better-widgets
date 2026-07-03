import WebKit

enum RenderError: Error {
    case timeout
    case snapshotFailed
}

@MainActor
final class RenderEngine: NSObject {
    private let readyGraceDelay: TimeInterval = 0.3
    private let hardTimeout: TimeInterval = 5.0

    func render(html: String, baseURL: URL?, context: RenderContext) async throws -> Data {
        let size = context.size.pointSize
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        let ready = ReadySignal()
        controller.add(ready, name: "bwReady")

        let bwScript = """
        window.BW = \(try context.bwJSON());
        window.BW.ready = function () { window.webkit.messageHandlers.bwReady.postMessage(true); };
        """
        controller.addUserScript(WKUserScript(source: bwScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = controller

        // Serve the template's own assets over a confined bwasset:// scheme; the
        // WebView gets no file:// access at all (see §7 sandbox hardening).
        let assetBase: URL?
        if let templateDir = baseURL {
            config.setURLSchemeHandler(TemplateAssetSchemeHandler(templateDir: templateDir),
                                       forURLScheme: TemplateAssetSchemeHandler.scheme)
            assetBase = URL(string: "\(TemplateAssetSchemeHandler.scheme)://template/")
        } else {
            assetBase = nil
        }

        let webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        webView.appearance = NSAppearance(named: context.theme == .dark ? .darkAqua : .aqua)
        webView.pageZoom = 2
        webView.setValue(false, forKey: "drawsBackground") // transparent by default; template paints its own bg

        let navDelegate = NavDelegate()
        webView.navigationDelegate = navDelegate

        webView.loadHTMLString(html, baseURL: assetBase)

        // Wait: BW.ready() wins immediately; otherwise didFinish + grace delay; hard timeout 5 s.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await ready.wait(orNavDone: navDelegate, grace: self.readyGraceDelay)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(self.hardTimeout))
                throw RenderError.timeout
            }
            try await group.next()
            group.cancelAll()
        }

        let snapConfig = WKSnapshotConfiguration()
        snapConfig.rect = CGRect(origin: .zero, size: size)
        snapConfig.snapshotWidth = NSNumber(value: Double(size.width) * 2)
        snapConfig.afterScreenUpdates = true

        // Guarded against a double-invocation: on some sizes WKWebView's legacy
        // takeSnapshot completion handler fires more than once (observed on the
        // 364pt-wide medium size — the first callback resumes the continuation,
        // a second call would otherwise crash the Swift Concurrency runtime with
        // a continuation-misuse error). Only the first callback wins.
        let image: NSImage = try await withCheckedThrowingContinuation { cont in
            var didResume = false
            webView.takeSnapshot(with: snapConfig) { image, error in
                guard !didResume else { return }
                didResume = true
                if let image { cont.resume(returning: image) } else {
                    cont.resume(throwing: error ?? RenderError.snapshotFailed)
                }
            }
        }

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw RenderError.snapshotFailed
        }
        controller.removeScriptMessageHandler(forName: "bwReady")
        return png
    }
}

/// Resolves when BW.ready() is posted, or navDone + grace delay elapses.
@MainActor
private final class ReadySignal: NSObject, WKScriptMessageHandler {
    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var isReady = false

    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        Task { @MainActor in
            self.isReady = true
            self.resumeIfWaiting()
        }
    }

    /// Waits for `BW.ready()`, or `didFinish` + `grace`, whichever comes first.
    ///
    /// Wrapped in `withTaskCancellationHandler` so that when the sibling hard-timeout
    /// task in `render()`'s task group wins the race and this task gets cancelled, the
    /// continuation resolves immediately instead of waiting on `nav.waitForFinish()` —
    /// which, for a template whose script never yields (e.g. `didFinish` never fires),
    /// would otherwise never resolve and defeat the whole point of the hard timeout:
    /// the outer task group awaits every child before returning, so a stuck child here
    /// would make `render()` hang indefinitely instead of bailing out at `hardTimeout`.
    func wait(orNavDone nav: NavDelegate, grace: TimeInterval) async {
        if isReady { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                readyContinuation = cont
                Task { @MainActor in
                    await nav.waitForFinish()
                    try? await Task.sleep(for: .seconds(grace))
                    self.resumeIfWaiting()
                }
            }
        } onCancel: {
            Task { @MainActor in self.resumeIfWaiting() }
        }
    }

    private func resumeIfWaiting() {
        guard let cont = readyContinuation else { return }
        readyContinuation = nil
        cont.resume()
    }
}

@MainActor
private final class NavDelegate: NSObject, WKNavigationDelegate {
    private var finished = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.finished = true
            self.continuations.forEach { $0.resume() }
            self.continuations.removeAll()
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(NavigationPolicy.decide(for: navigationAction.request.url))
    }

    func waitForFinish() async {
        if finished { return }
        await withCheckedContinuation { continuations.append($0) }
    }
}
