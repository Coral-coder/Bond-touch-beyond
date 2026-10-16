import CoreLocation
import Foundation

/// Thin CoreLocation wrapper: requests when-in-use permission and publishes the current
/// coordinate. Used by Presence to share the user's live location with their partner.
final class LocationService: NSObject, ObservableObject {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var authorized = false

    /// Called on the main thread with each new coordinate.
    var onUpdate: ((CLLocationCoordinate2D) -> Void)?

    private let manager = CLLocationManager()
    private var running = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
    }

    func start() {
        guard !running else { return }
        running = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        running = false
        manager.stopUpdatingLocation()
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        DispatchQueue.main.async {
            self.coordinate = coord
            self.onUpdate?(coord)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let ok = manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
        DispatchQueue.main.async { self.authorized = ok }
    }
}
