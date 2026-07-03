import XCTest
// No module import: Core sources are compiled directly into the test target.

final class RenderEngineTests: XCTestCase {
    // HTML: red background in light, blue in dark, displays BW.params.label.
    private let html = """
    <!doctype html><html><head><meta charset="utf-8"><style>
      html, body { margin: 0; width: 100%; height: 100%; }
      body { background: #ff0000; }
      @media (prefers-color-scheme: dark) { body { background: #0000ff; } }
    </style></head><body><script>
      document.body.textContent = window.BW.params.label;
    </script></body></html>
    """

    private var assetTemplateDir: URL!

    override func tearDownWithError() throws {
        if let dir = assetTemplateDir { try? FileManager.default.removeItem(at: dir) }
    }

    @MainActor
    func testRendersLightPNGAtExactSize() async throws {
        let engine = RenderEngine()
        let ctx = RenderContext(params: ["label": "hello"], data: [:], size: .small, theme: .light, stale: false)
        let png = try await engine.render(html: html, baseURL: nil, context: ctx)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(rep.pixelsWide, 340)  // 170pt @2x
        XCTAssertEqual(rep.pixelsHigh, 340)
        let center = try XCTUnwrap(rep.colorAt(x: 170, y: 170)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(center.redComponent, 0.8, "light theme must render the red background")
        XCTAssertLessThan(center.blueComponent, 0.2)
    }

    @MainActor
    func testRendersDarkVariant() async throws {
        let engine = RenderEngine()
        let ctx = RenderContext(params: ["label": "hello"], data: [:], size: .small, theme: .dark, stale: false)
        let png = try await engine.render(html: html, baseURL: nil, context: ctx)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        let center = try XCTUnwrap(rep.colorAt(x: 170, y: 170)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(center.blueComponent, 0.8, "dark theme must render the blue background")
    }

    @MainActor
    func testMediumSizeDimensions() async throws {
        let engine = RenderEngine()
        let ctx = RenderContext(params: [:], data: [:], size: .medium, theme: .light, stale: false)
        let png = try await engine.render(html: html, baseURL: nil, context: ctx)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(rep.pixelsWide, 728)
        XCTAssertEqual(rep.pixelsHigh, 340)
    }

    // Not in the original brief: added after a code-review pass found that the hard
    // timeout wasn't actually enforced when a template's script never yields control
    // (so `didFinish` never fires and `BW.ready()` is never called) — see the fix and
    // comment on `ReadySignal.wait` in RenderEngine.swift. This locks that fix in.
    @MainActor
    func testTimesOutOnHangingTemplate() async throws {
        let engine = RenderEngine()
        let hangingHTML = "<!doctype html><html><body><script>while (true) {}</script></body></html>"
        let ctx = RenderContext(params: [:], data: [:], size: .small, theme: .light, stale: false)
        let start = Date()
        do {
            _ = try await engine.render(html: hangingHTML, baseURL: nil, context: ctx)
            XCTFail("expected RenderError.timeout for a template whose script never yields")
        } catch RenderError.timeout {
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertLessThan(elapsed, 6.5, "the hard timeout must actually bound render() latency")
        }
    }

    // Not in the original brief: added after a code-review pass found that the ONLY
    // production path (`baseURL != nil`, wired to the `bwasset://` scheme handler via
    // RenderPipeline) had no committed test exercising it through a real WKWebView — every
    // other RenderEngineTests case renders with `baseURL: nil`. A typo in the scheme wiring
    // (registration string, base URL string) would leave the whole suite green while breaking
    // every real render. This fetches an asset over `bwasset://template/` and paints the fetched
    // value, proving the scheme handler is actually reachable from a live render.
    @MainActor
    func testRendersAssetServedOverBwassetScheme() async throws {
        assetTemplateDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: assetTemplateDir, withIntermediateDirectories: true)
        try "#00ff00".write(to: assetTemplateDir.appendingPathComponent("color.txt"), atomically: true, encoding: .utf8)

        let assetHTML = """
        <!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;width:100%;height:100%}</style></head>
        <body><script>
          fetch('bwasset://template/color.txt').then(r=>r.text()).then(c=>{
            document.body.style.background = c.trim();
            window.BW.ready();
          }).catch(e=>{ document.body.style.background='#ff0000'; window.BW.ready(); });
        </script></body></html>
        """

        let engine = RenderEngine()
        let ctx = RenderContext(params: [:], data: [:], size: .small, theme: .light, stale: false)
        let png = try await engine.render(html: assetHTML, baseURL: assetTemplateDir, context: ctx)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        let center = try XCTUnwrap(rep.colorAt(x: 170, y: 170)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(center.greenComponent, 0.8, "the asset served over bwasset:// must have been painted")
        XCTAssertLessThan(center.redComponent, 0.2)
    }
}
