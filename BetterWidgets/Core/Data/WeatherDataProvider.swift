import Foundation
import CoreLocation
import WeatherKit

struct WeatherDTO: Equatable {
    let temperature: Double
    let conditionCode: String
    let symbolName: String
    let humidity: Double
}

protocol WeatherFetching {
    func currentWeather(latitude: Double, longitude: Double) async throws -> WeatherDTO
}

/// Real WeatherKit implementation. Not exercised by unit tests — requires the
/// WeatherKit capability + key provisioned in the Apple Developer portal.
struct WeatherKitService: WeatherFetching {
    func currentWeather(latitude: Double, longitude: Double) async throws -> WeatherDTO {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let current = try await WeatherService.shared.weather(for: location, including: .current)
        return WeatherDTO(temperature: current.temperature.value,
                          conditionCode: "\(current.condition)",
                          symbolName: current.symbolName,
                          humidity: current.humidity)
    }
}

/// Geocodes a city name to coordinates via CoreLocation (no entitlement needed).
func geocodeCity(_ city: String) async throws -> (lat: Double, lon: Double) {
    let placemarks = try await CLGeocoder().geocodeAddressString(city)
    guard let location = placemarks.first?.location else {
        throw DataProviderError.badURL("cannot geocode city '\(city)'")
    }
    return (location.coordinate.latitude, location.coordinate.longitude)
}

struct WeatherDataProvider: DataProvider {
    static let type = "weather"
    let minimumInterval: TimeInterval = 900
    let fetcher: WeatherFetching
    let geocoder: (String) async throws -> (lat: Double, lon: Double)

    init(fetcher: WeatherFetching,
         geocoder: @escaping (String) async throws -> (lat: Double, lon: Double)) {
        self.fetcher = fetcher
        self.geocoder = geocoder
    }

    func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
        let coords: (lat: Double, lon: Double)
        if let latStr = spec.config?["lat"], let lonStr = spec.config?["lon"],
           let lat = Double(substituteParams(latStr, params: paramValues)),
           let lon = Double(substituteParams(lonStr, params: paramValues)) {
            coords = (lat, lon)
        } else if let city = spec.config?["city"] {
            coords = try await geocoder(substituteParams(city, params: paramValues))
        } else {
            throw DataProviderError.missingConfig("weather source '\(spec.key)' requires lat+lon or city")
        }
        let weather = try await fetcher.currentWeather(latitude: coords.lat, longitude: coords.lon)
        return [
            "temperature": weather.temperature,
            "condition": weather.conditionCode,
            "symbol": weather.symbolName,
            "humidity": weather.humidity,
        ]
    }
}
