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
    /// Called on the main thread when the phone arrives at a saved place (its id).
    var onArrive: ((String) -> Void)?

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
        // Keep updating with the app in the background (it's kept running for the bracelet),
        // so the partner's card shows live movement and speed, not where you were when you
        // last opened the app.
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stop() {
        running = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    /// Watches the saved places (iOS wakes the app on arrival, even when it's closed). Needs
    /// "Always" location access, asked for the first time a place is watched.
    func monitor(_ places: [SavedPlace]) {
        let wanted = Set(places.map(\.id.uuidString))
        for region in manager.monitoredRegions where region.identifier.hasPrefix(SavedPlace.prefix)
            && !wanted.contains(String(region.identifier.dropFirst(SavedPlace.prefix.count))) {
            manager.stopMonitoring(for: region)
        }
        guard !places.isEmpty, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        if manager.authorizationStatus != .authorizedAlways { manager.requestAlwaysAuthorization() }
        for place in places.prefix(20) {   // iOS watches at most 20 regions per app
            let region = CLCircularRegion(center: place.coordinate, radius: place.radius,
                                          identifier: SavedPlace.prefix + place.id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
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

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix(SavedPlace.prefix) else { return }
        let id = String(region.identifier.dropFirst(SavedPlace.prefix.count))
        DispatchQueue.main.async { self.onArrive?(id) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let ok = manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
        DispatchQueue.main.async { self.authorized = ok }
    }
}
