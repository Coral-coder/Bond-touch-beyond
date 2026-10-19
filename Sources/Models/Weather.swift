import Foundation

/// The weather somewhere: now, the next hours and the next days, from Open-Meteo.
/// Your phone looks it up for where your partner is (from the location they share); if they
/// don't share their location, their phone's own lookup (shared in their sealed status) is
/// shown instead.
struct WeatherInfo: Codable, Equatable {
    struct Hour: Codable, Equatable { var at: Date; var temp: Double; var symbol: String }
    struct Day: Codable, Equatable { var date: Date; var high: Double; var low: Double; var symbol: String }

    /// Town or city, when it could be named.
    var place: String?
    /// °C.
    var temp: Double
    /// SF Symbol name.
    var symbol: String
    /// "Partly Cloudy".
    var summary: String
    var high: Double?
    var low: Double?
    var hours: [Hour] = []
    var days: [Day] = []
    var fetchedAt = Date()
    /// The phone's time zone, so their local time can be shown.
    var timeZone: String?

    /// "64°" or "18°", in the units picked in Settings (Automatic follows the phone's region).
    static func degrees(_ celsius: Double) -> String {
        let value = Units.imperial ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }
}

/// Imperial (°F, miles) or metric (°C, km): Settings → Units. "auto" follows the region.
enum Units {
    static let key = "units"
    /// Set by the widgets from the app's snapshot (they don't share the app's settings).
    static var override: String?
    static var choice: String { override ?? UserDefaults.standard.string(forKey: key) ?? "auto" }
    static var imperial: Bool {
        switch choice {
        case "imperial": return true
        case "metric": return false
        default: return Locale.current.measurementSystem == .us
        }
    }
}
