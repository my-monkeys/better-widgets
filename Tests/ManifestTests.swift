import XCTest

final class ManifestTests: XCTestCase {
    private func manifestJSON(refresh: Int = 900, sourceType: String = "system") -> Data {
        """
        {
          "id": "weather-minimal", "name": "Météo minimale", "version": "1.0.0",
          "sizes": ["small", "medium"], "refresh": \(refresh),
          "params": [{ "key": "city", "type": "string", "label": "Ville", "default": "Montpellier" }],
          "sources": [{ "key": "sys", "type": "\(sourceType)" }]
        }
        """.data(using: .utf8)!
    }

    func testValidManifestParses() throws {
        let m = try TemplateManifest.validated(from: manifestJSON())
        XCTAssertEqual(m.id, "weather-minimal")
        XCTAssertEqual(m.sizes, [.small, .medium])
        XCTAssertEqual(m.refresh, 900)
        XCTAssertEqual(m.params.first?.default, "Montpellier")
        XCTAssertNil(m.links)
    }

    func testRefreshUnder30sRejected() {
        XCTAssertThrowsError(try TemplateManifest.validated(from: manifestJSON(refresh: 5))) {
            XCTAssertEqual($0 as? ManifestError, .refreshTooSmall)
        }
    }

    func testUnknownSourceTypeRejected() {
        XCTAssertThrowsError(try TemplateManifest.validated(from: manifestJSON(sourceType: "crypto"))) {
            XCTAssertEqual($0 as? ManifestError, .unknownSourceType("crypto"))
        }
    }

    func testDuplicateParamKeyRejected() {
        let json = """
        { "id": "x", "name": "x", "version": "1", "sizes": ["small"], "refresh": 60,
          "params": [{"key":"a","type":"string","label":"A"},{"key":"a","type":"string","label":"A2"}],
          "sources": [] }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try TemplateManifest.validated(from: json)) {
            XCTAssertEqual($0 as? ManifestError, .duplicateParamKey("a"))
        }
    }

    func testGarbageJSONGivesReadableError() {
        XCTAssertThrowsError(try TemplateManifest.validated(from: Data("not json".utf8)))
    }
}
