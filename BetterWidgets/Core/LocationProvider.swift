import Foundation
import CoreLocation

protocol LocationProvider {
    func currentCoordinates() async throws -> (lat: Double, lon: Double)
}

/// Real CoreLocation-backed provider. Requests one location fix; the system TCC
/// prompt is the authority. Not exercised by unit tests.
final class CoreLocationProvider: NSObject, LocationProvider, CLLocationManagerDelegate {
    private var continuation: CheckedContinuation<(lat: Double, lon: Double), Error>?
    private let manager = CLLocationManager()

    func currentCoordinates() async throws -> (lat: Double, lon: Double) {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        continuation?.resume(returning: (loc.coordinate.latitude, loc.coordinate.longitude))
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
