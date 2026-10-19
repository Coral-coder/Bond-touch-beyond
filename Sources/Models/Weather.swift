import Foundation

/// The weather somewhere: now, the next hours and the next days, from Apple's WeatherKit.
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
    /// SF Symbol name, as WeatherKit gives it.
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

    /// "18°" in the viewer's own units.
    static func degrees(_ celsius: Double) -> String {
        let m = Measurement(value: celsius, unit: UnitTemperature.celsius)
        let f = MeasurementFormatter()
        f.numberFormatter.maximumFractionDigits = 0
        f.unitOptions = .temperatureWithoutUnit
        return f.string(from: m)
    }
}
