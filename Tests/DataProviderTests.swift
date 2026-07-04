import XCTest

/// Intercepts requests so provider tests can assert a fetch was *attempted*
/// (i.e. passed the scheme/host gate) without touching the network.
final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
    static func respondOK(_ json: String) {
        handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(json.utf8))
        }
    }
}

final class DataProviderTests: XCTestCase {

    func testSubstituteParams() {
        XCTAssertEqual(substituteParams("https://api.x/{{city}}/now?u={{unit}}",
                                        params: ["city": "montpellier", "unit": "c"]),
                       "https://api.x/montpellier/now?u=c")
        XCTAssertEqual(substituteParams("no params", params: [:]), "no params")
    }

    func testSystemProviderShape() async throws {
        let provider = SystemDataProvider()
        let spec = SourceSpec(key: "sys", type: "system", config: nil)
        let result = try await provider.fetch(spec: spec, paramValues: [:])
        let dict = try XCTUnwrap(result as? [String: Any])
        XCTAssertNotNil(dict["datetime"] as? String)
        XCTAssertNotNil(dict["uptime"] as? Double)
        XCTAssertNotNil(dict["memTotal"] as? Double)
        XCTAssertNotNil(dict["diskFree"] as? Double)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(dict), "must be JSON-serializable")
    }

    func testJSONProviderMissingURLConfigThrows() async {
        let provider = JSONDataProvider(urlSession: .shared)
        let spec = SourceSpec(key: "api", type: "json", config: nil)
        do {
            _ = try await provider.fetch(spec: spec, paramValues: [:])
            XCTFail("expected missingConfig")
        } catch { /* expected */ }
    }

    func testJSONProviderRejectsPublicHTTP() async {
        MockURLProtocol.respondOK("{}")  // would succeed if the gate let it through
        let provider = JSONDataProvider(urlSession: MockURLProtocol.session())
        for url in ["http://example.com/x", "http://8.8.8.8/x"] {
            do {
                _ = try await provider.fetch(
                    spec: SourceSpec(key: "a", type: "json", config: ["url": url]), paramValues: [:])
                XCTFail("expected badURL for public http \(url)")
            } catch { /* expected: rejected before any network call */ }
        }
    }

    func testJSONProviderAllowsPrivateHTTP() async throws {
        MockURLProtocol.respondOK(#"{"ok":true}"#)
        let provider = JSONDataProvider(urlSession: MockURLProtocol.session())
        let result = try await provider.fetch(
            spec: SourceSpec(key: "a", type: "json",
                             config: ["url": "http://100.100.100.100:2300/api/x"]), paramValues: [:])
        let dict = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(dict["ok"] as? Bool, true)
    }

    func testJSONProviderAllowsHTTPS() async throws {
        MockURLProtocol.respondOK(#"{"ok":true}"#)
        let provider = JSONDataProvider(urlSession: MockURLProtocol.session())
        let result = try await provider.fetch(
            spec: SourceSpec(key: "a", type: "json",
                             config: ["url": "https://api.example.com/x"]), paramValues: [:])
        let dict = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(dict["ok"] as? Bool, true)
    }

    func testRegistryFetchAllCollectsFailuresAsFailedKeys() async {
        struct BoomProvider: DataProvider {
            static let type = "boom"
            let minimumInterval: TimeInterval = 60
            func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
                throw DataProviderError.missingConfig("boom")
            }
        }
        let registry = DataProviderRegistry(providers: [SystemDataProvider(), BoomProvider()])
        let sources = [SourceSpec(key: "sys", type: "system", config: nil),
                       SourceSpec(key: "b", type: "boom", config: nil)]
        let result = await registry.fetchAll(sources: sources, paramValues: [:])
        XCTAssertNotNil(result.data["sys"])
        XCTAssertNil(result.data["b"])
        XCTAssertEqual(result.failedKeys, ["b"])
    }

    func testRegistryUnknownTypeIsFailedKey() async {
        let registry = DataProviderRegistry(providers: [SystemDataProvider()])
        let result = await registry.fetchAll(
            sources: [SourceSpec(key: "x", type: "nope", config: nil)], paramValues: [:])
        XCTAssertEqual(result.failedKeys, ["x"])
    }

    func testRegistryDuplicateTypeDoesNotTrapAndFirstWins() async {
        struct FirstProvider: DataProvider {
            static let type = "dup"
            let minimumInterval: TimeInterval = 60
            func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
                ["who": "first"]
            }
        }
        struct SecondProvider: DataProvider {
            static let type = "dup"
            let minimumInterval: TimeInterval = 60
            func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
                ["who": "second"]
            }
        }
        // Construction must not trap even though both providers share `type == "dup"`.
        let registry = DataProviderRegistry(providers: [FirstProvider(), SecondProvider()])
        let result = await registry.fetchAll(
            sources: [SourceSpec(key: "d", type: "dup", config: nil)], paramValues: [:])
        let dict = try? XCTUnwrap(result.data["d"] as? [String: String])
        XCTAssertEqual(dict, ["who": "first"])
        XCTAssertEqual(result.failedKeys, [])
    }
}
