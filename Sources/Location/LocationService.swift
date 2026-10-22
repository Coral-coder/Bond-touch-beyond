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
    private(set) var running = false
    private var lastRequest = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        setBackground(false)
    }

    /// On screen: 100 m fixes every 25 m, for the live map. In the background: cell / Wi-Fi
    /// fixes (no GPS) every 500 m, so sharing costs little battery and leaves the GPS to
    /// navigation apps.
    func setBackground(_ background: Bool) {
        manager.desiredAccuracy = background ? kCLLocationAccuracyKilometer : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = background ? 500 : 25
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

    /// A rough position for the weather when live updates are off: the system's last known
    /// fix, and a one-off request for a fresh one (if location access was given) when that is
    /// over 30 minutes old — at most every 30 minutes.
    var roughFix: CLLocation? {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            let known = lastLocation ?? manager.location
            if !running, Date().timeIntervalSince(known?.timestamp ?? .distantPast) > 30 * 60,
               Date().timeIntervalSince(lastRequest) > 30 * 60 {
                lastRequest = Date()
                manager.requestLocation()
            }
            return known
        }
        return lastLocation
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

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

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
