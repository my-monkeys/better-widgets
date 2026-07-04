import XCTest
// Core sources are compiled directly into the test target (no module import).

enum BundledTemplates {
    static let ids = ["weather", "crypto", "system", "news", "agenda", "status", "home", "github"]

    /// Source-tree templates dir, resolved from this file's path so tests read the real
    /// bundled templates without adding them to the test bundle's resources.
    static var dir: URL {
        URL(fileURLWithPath: #filePath)          // …/Tests/BundledTemplateTests.swift
            .deletingLastPathComponent()          // …/Tests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("BetterWidgets/Resources/templates")
    }
    static func manifest(_ id: String) throws -> TemplateManifest {
        try TemplateManifest.validated(from: Data(contentsOf: dir.appendingPathComponent("\(id)/manifest.json")))
    }
    static func html(_ id: String) throws -> String {
        try String(contentsOf: dir.appendingPathComponent("\(id)/index.html"), encoding: .utf8)
    }
    static func defaultParams(_ m: TemplateManifest) -> [String: String] {
        var p: [String: String] = [:]
        for spec in m.params { if let d = spec.default { p[spec.key] = d } }
        return p
    }
}

final class BundledTemplateTests: XCTestCase {

    /// Renders `id` for every declared size × light/dark, asserting exact @2x dimensions.
    @MainActor
    func assertRenders(_ id: String, data: [String: Any]) async throws {
        let manifest = try BundledTemplates.manifest(id)
        let html = try BundledTemplates.html(id)
        let dir = BundledTemplates.dir.appendingPathComponent(id)
        let params = BundledTemplates.defaultParams(manifest)
        for size in manifest.sizes {
            for theme in [Theme.light, .dark] {
                let ctx = RenderContext(params: params, data: data, size: size, theme: theme, stale: false)
                let png = try await RenderEngine().render(html: html, baseURL: dir, context: ctx)
                let rep = try XCTUnwrap(NSBitmapImageRep(data: png), "\(id) \(size) \(theme) produced no PNG")
                XCTAssertEqual(rep.pixelsWide, Int(size.pointSize.width * 2), "\(id) \(size) width")
                XCTAssertEqual(rep.pixelsHigh, Int(size.pointSize.height * 2), "\(id) \(size) height")
            }
        }
    }

    func testWeatherManifestValid() throws {
        let m = try BundledTemplates.manifest("weather")
        XCTAssertEqual(m.id, "weather")
        XCTAssertEqual(m.sources.first?.type, "json")
    }

    @MainActor
    func testWeatherRenders() async throws {
        let data: [String: Any] = ["wx": [
            "current": ["temperature_2m": 21.4, "weather_code": 1],
            "daily": [
                "time": ["2026-07-05", "2026-07-06", "2026-07-07", "2026-07-08", "2026-07-09"],
                "temperature_2m_max": [27.0, 29.0, 25.0, 22.0, 24.0],
                "temperature_2m_min": [15.0, 16.0, 14.0, 13.0, 14.0],
                "weather_code": [0, 1, 2, 61, 3]
            ]
        ]]
        try await assertRenders("weather", data: data)
    }

    func testCryptoManifestValid() throws {
        let m = try BundledTemplates.manifest("crypto")
        XCTAssertEqual(m.sources.count, 2)
        XCTAssertEqual(Set(m.sources.map { $0.key }), ["price", "chart"])
    }

    @MainActor
    func testCryptoRenders() async throws {
        let prices: [Double] = (0..<48).map { 66000 + Double($0) * 40 }
        let data: [String: Any] = [
            "price": ["bitcoin": ["usd": 67432, "usd_24h_change": 2.4],
                      "ethereum": ["usd": 3518, "usd_24h_change": -1.1]],
            "chart": ["prices": prices.map { [1_700_000_000_000.0, $0] }]
        ]
        try await assertRenders("crypto", data: data)
    }
}
