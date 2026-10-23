import CoreLocation
import Observation
import OpenTransportCore

/// The user's position for distances and "near me" (Android polls the fused
/// provider every 10 s; CoreLocation pushes updates instead).
@MainActor
@Observable
final class LocationModel: NSObject, CLLocationManagerDelegate {
    private(set) var location: LonLat?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            location = nil
        }
    }

    func distance(to lat: Double, _ lon: Double) -> Double? {
        location.map { TransitMotion.distanceMeters($0, LonLat(lon: lon, lat: lat)) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.start() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let point = LonLat(lon: last.coordinate.longitude, lat: last.coordinate.latitude)
        Task { @MainActor in self.location = point }
    }
}
