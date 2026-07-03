import XCTest

final class RSSDataProviderTests: XCTestCase {
    func testTypeAndInterval() {
        XCTAssertEqual(RSSDataProvider.type, "rss")
        XCTAssertGreaterThanOrEqual(RSSDataProvider(urlSession: .shared).minimumInterval, 900)
    }

    func testMissingURLThrows() async {
        do {
            _ = try await RSSDataProvider(urlSession: .shared)
                .fetch(spec: SourceSpec(key: "f", type: "rss", config: nil), paramValues: [:])
            XCTFail("expected throw")
        } catch { /* expected */ }
    }

    func testNonHttpsRejected() async {
        do {
            _ = try await RSSDataProvider(urlSession: .shared)
                .fetch(spec: SourceSpec(key: "f", type: "rss", config: ["url": "http://ex.com/feed"]),
                       paramValues: [:])
            XCTFail("expected throw")
        } catch { /* expected */ }
    }

    func testRegistryIncludesRSS() {
        // .standard() must route "rss" to a provider (otherwise every rss source fails).
        let registry = DataProviderRegistry.standard()
        // Indirect check: an rss source with a bad URL should FAIL (routed, then errors),
        // not be an unknown-type no-op. We assert it lands in failedKeys, meaning it was routed.
        let exp = expectation(description: "fetch")
        Task {
            let r = await registry.fetchAll(
                sources: [SourceSpec(key: "f", type: "rss", config: ["url": "https://0.0.0.0/nope"])],
                paramValues: [:])
            XCTAssertEqual(r.failedKeys, ["f"])
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }
}
