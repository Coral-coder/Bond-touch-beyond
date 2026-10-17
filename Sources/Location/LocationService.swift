import CoreLocation
import Foundation

/// Thin CoreLocation wrapper: requests when-in-use permission and publishes the current
/// coordinate. Used by Presence to share the user's live location with their partner.
final class LocationService: NSObject, ObservableObject {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var authorized = false
    /// The latest fix (with its timestamp) and the speed there in m/s, when known.
    private(set) var lastLocation: CLLocation?
    private(set) var speed: Double?

    /// Called on the main thread with each new fix.
    var onUpdate: ((CLLocation) -> Void)?

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
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            // Speed straight from the fix when valid; otherwise distance over time since the
            // previous fix (only across a sensible gap, so jitter doesn't read as movement).
            if location.speed >= 0, location.speedAccuracy >= 0 {
                self.speed = location.speed
            } else if let previous = self.lastLocation {
                let dt = location.timestamp.timeIntervalSince(previous.timestamp)
                self.speed = (5...600).contains(dt) ? location.distance(from: previous) / dt : nil
            } else {
                self.speed = nil
            }
            self.lastLocation = location
            self.coordinate = location.coordinate
            self.onUpdate?(location)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let ok = manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
        DispatchQueue.main.async { self.authorized = ok }
    }
}
