import CoreLocation
import Foundation

/// A place the user saved (Home, Work…). Arriving there sends partners a touch saying so,
/// as the original's arrival alerts.
struct SavedPlace: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    /// Metres around the point that count as "there".
    var radius: Double = 150
    /// Whether arriving here tells partners.
    var notifyPartners = true

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    /// Region identifiers start with this, so the app's other regions are left alone.
    static let prefix = "place-"
}
