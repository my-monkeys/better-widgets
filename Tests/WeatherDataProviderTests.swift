import XCTest

final class WeatherDataProviderTests: XCTestCase {
    private struct FakeWeather: WeatherFetching {
        let dto: WeatherDTO
        var lastCoords: (Double, Double)?
        func currentWeather(latitude: Double, longitude: Double) async throws -> WeatherDTO {
            return dto
        }
    }
    private let sample = WeatherDTO(temperature: 21.5, conditionCode: "Clear",
                                    symbolName: "sun.max", humidity: 0.4)

    private struct FakeLocation: LocationProvider {
        var coords: (lat: Double, lon: Double) = (48.85, 2.35)
        var thrown: Error?
        func currentCoordinates() async throws -> (lat: Double, lon: Double) {
            if let thrown { throw thrown }
            return coords
        }
    }

    func testTypeAndInterval() {
        let p = WeatherDataProvider(fetcher: FakeWeather(dto: sample), geocoder: { _ in (0, 0) })
        XCTAssertEqual(WeatherDataProvider.type, "weather")
        XCTAssertGreaterThanOrEqual(p.minimumInterval, 900)
    }

    func testUsesExplicitLatLon() async throws {
        let p = WeatherDataProvider(fetcher: FakeWeather(dto: sample), geocoder: { _ in
            XCTFail("geocoder must not be called when lat/lon provided"); return (0, 0)
        })
        let result = try await p.fetch(
            spec: SourceSpec(key: "w", type: "weather", config: ["lat": "43.6", "lon": "3.87"]),
            paramValues: [:])
        let dict = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(dict["temperature"] as? Double, 21.5)
        XCTAssertEqual(dict["condition"] as? String, "Clear")
        XCTAssertEqual(dict["symbol"] as? String, "sun.max")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(dict))
    }

    func testGeocodesCityWhenNoLatLon() async throws {
        var geocoded = false
        let p = WeatherDataProvider(fetcher: FakeWeather(dto: sample), geocoder: { city in
            geocoded = true
            XCTAssertEqual(city, "Montpellier")
            return (43.6, 3.87)
        })
        _ = try await p.fetch(spec: SourceSpec(key: "w", type: "weather", config: ["city": "Montpellier"]),
                              paramValues: [:])
        XCTAssertTrue(geocoded)
    }

    func testMissingLocationThrows() async {
        let p = WeatherDataProvider(fetcher: FakeWeather(dto: sample), geocoder: { _ in (0, 0) })
        do {
            _ = try await p.fetch(spec: SourceSpec(key: "w", type: "weather", config: nil), paramValues: [:])
            XCTFail("expected throw")
        } catch { /* expected */ }
    }

    func testUsesCurrentLocationWhenConfigured() async throws {
        let loc = FakeLocation(coords: (10, 20))
        var calledGeocoder = false
        let p = WeatherDataProvider(fetcher: FakeWeather(dto: sample),
                                    geocoder: { _ in calledGeocoder = true; return (0, 0) },
                                    location: loc)
        let result = try await p.fetch(
            spec: SourceSpec(key: "w", type: "weather", config: ["useCurrentLocation": "true", "city": "Paris"]),
            paramValues: [:])
        XCTAssertNotNil(result as? [String: Any])       // succeeded via current location
        XCTAssertFalse(calledGeocoder)                  // city/geocoder ignored when useCurrentLocation
    }

    func testCurrentLocationFailurePropagates() async {
        let loc = FakeLocation(thrown: DataProviderError.badURL("no location"))
        let p = WeatherDataProvider(fetcher: FakeWeather(dto: sample),
                                    geocoder: { _ in (0, 0) }, location: loc)
        do {
            _ = try await p.fetch(spec: SourceSpec(key: "w", type: "weather", config: ["useCurrentLocation": "true"]),
                                  paramValues: [:])
            XCTFail("expected throw")
        } catch { /* expected */ }
    }
}
