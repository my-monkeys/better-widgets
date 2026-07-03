import XCTest

final class Plan2ManifestTests: XCTestCase {
    private func manifest(type: String) -> Data {
        """
        { "id": "t", "name": "T", "version": "1.0.0", "sizes": ["medium"], "refresh": 900,
          "params": [], "sources": [{ "key": "s", "type": "\(type)" }] }
        """.data(using: .utf8)!
    }

    func testNewSourceTypesValidate() throws {
        for type in ["rss", "calendar", "weather"] {
            XCTAssertNoThrow(try TemplateManifest.validated(from: manifest(type: type)),
                             "\(type) should be a known source type")
        }
    }

    func testConsentFlagOnlyForCalendarAndWeather() {
        XCTAssertTrue(SourceSpec(key: "s", type: "calendar", config: nil).requiresConsent)
        XCTAssertTrue(SourceSpec(key: "s", type: "weather", config: nil).requiresConsent)
        XCTAssertFalse(SourceSpec(key: "s", type: "rss", config: nil).requiresConsent)
        XCTAssertFalse(SourceSpec(key: "s", type: "system", config: nil).requiresConsent)
    }
}
