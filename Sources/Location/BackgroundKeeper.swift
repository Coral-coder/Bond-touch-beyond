import CoreLocation
import Foundation

/// Keeps the app running in the background so touches from partners are received and
/// played on the bracelet, and touches made on the bracelet are sent, while the phone is
/// locked.
///
/// Partners wake the app with silent pushes, and the bracelet's own events wake it over
/// Bluetooth; but iOS throttles (and, once the app is swiped away, drops) silent pushes,
/// so kept running the app keeps checking iCloud. Low-accuracy background location
/// (cell/Wi-Fi, no GPS) is what lets an app keep running; iOS shows the blue location
/// indicator while it's on. Off in Settings, or automatically when no partner needs it.
final class BackgroundKeeper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var running = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        // Only to keep the app running: one wake per 3 km is plenty.
        manager.distanceFilter = 3000
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
    }

    /// Start while the app is in the foreground (iOS requires that for background location
    /// with "While Using" permission).
    func start() {
        guard !running else { return }
        running = true
        manager.requestWhenInUseAuthorization()
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
