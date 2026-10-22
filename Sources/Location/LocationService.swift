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
    private var background = false
    private var lastRequest = Date.distantPast
    /// Callers of `freshFix()` waiting for the next fix.
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = false
        manager.desiredAccuracy = kCLLocationAccuracyKilometer   // the weather's rough fix
    }

    /// Like Find My: live 100 m updates only while the app is on screen. In the background
    /// the system's own low-power watchers take over — significant changes (cell / Wi-Fi,
    /// about every 500 m) and visits (arriving / leaving a place) — so sharing keeps no GPS
    /// on and leaves it to navigation apps. A partner who opens the map asks for a fresh fix
    /// with a background push (`freshFix()`).
    func setBackground(_ background: Bool) {
        self.background = background
        if running { applyMode() }
    }

    private func applyMode() {
        // Significant changes and visits need "Always" access; with "While Using" the
        // background falls back to cell / Wi-Fi updates (1 km, every 500 m) — still no GPS.
        let lowPower = manager.authorizationStatus == .authorizedAlways
            && CLLocationManager.significantLocationChangeMonitoringAvailable()
        manager.desiredAccuracy = background ? kCLLocationAccuracyKilometer : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = background ? 500 : 25
        if background && lowPower {
            manager.stopUpdatingLocation()
            manager.startMonitoringSignificantLocationChanges()
            manager.startMonitoringVisits()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
            manager.stopMonitoringVisits()
            manager.startUpdatingLocation()
        }
    }

    func start() {
        guard !running else { return }
        running = true
        manager.requestWhenInUseAuthorization()
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
        applyMode()
    }

    func stop() {
        running = false
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        manager.allowsBackgroundLocationUpdates = false
    }

    /// One fresh fix (100 m), for a partner's "where are you?" push: the latest one if it's
    /// under a minute old, else a one-off request — given up after 10 s.
    func freshFix() async -> CLLocation? {
        if let last = lastLocation, Date().timeIntervalSince(last.timestamp) < 60 { return last }
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return nil }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            lastRequest = Date()
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.requestLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.finishWaiting(nil) }
        }
    }

    private func finishWaiting(_ fix: CLLocation?) {
        guard !waiting.isEmpty else { return }
        let all = waiting
        waiting = []
        manager.desiredAccuracy = running && !background ? kCLLocationAccuracyHundredMeters : kCLLocationAccuracyKilometer
        all.forEach { $0.resume(returning: fix ?? lastLocation) }
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
            self.finishWaiting(location)
        }
    }

    /// Arrived at or left a place (background): counts as a fix.
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let at = visit.departureDate == .distantFuture ? visit.arrivalDate : visit.departureDate
        let fix = CLLocation(coordinate: visit.coordinate, altitude: 0, horizontalAccuracy: visit.horizontalAccuracy,
                             verticalAccuracy: -1, timestamp: min(at, Date()))
        self.locationManager(manager, didUpdateLocations: [fix])
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.finishWaiting(nil) }
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
