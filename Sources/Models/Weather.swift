import CoreLocation
import Foundation

/// The weather where a phone is: now, the next hours and the next days. Each phone looks up
/// its own (Open-Meteo: free, no account; the position sent is rounded to about 10 km) and
/// shares it with partners inside its sealed status snapshot, so you see the weather where
/// your partner is even when they don't share their exact location.
struct WeatherInfo: Codable, Equatable {
    struct Hour: Codable, Equatable { var at: Date; var temp: Double; var code: Int; var isDay: Bool }
    struct Day: Codable, Equatable { var date: Date; var high: Double; var low: Double; var code: Int }

    /// Town or city, when it could be named.
    var place: String?
    var temp: Double
    var code: Int
    var isDay: Bool
    var high: Double?
    var low: Double?
    var hours: [Hour] = []
    var days: [Day] = []
    var fetchedAt = Date()
    /// The phone's time zone, so their local time can be shown.
    var timeZone: String?

    /// An SF Symbol for a WMO weather code.
    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: return "cloud.rain.fill"
        case 65, 67, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func text(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63: return "Rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "—"
        }
    }

    /// "18°" in the viewer's own units.
    static func degrees(_ celsius: Double) -> String {
        let m = Measurement(value: celsius, unit: UnitTemperature.celsius)
        let f = MeasurementFormatter()
        f.numberFormatter.maximumFractionDigits = 0
        f.unitOptions = .temperatureWithoutUnit
        return f.string(from: m)
    }
}

/// Fetches this phone's weather, at most every 30 minutes.
actor WeatherService {
    static let shared = WeatherService()
    private var cached: WeatherInfo?
    private var cachedAt: CLLocation?

    func weather(at location: CLLocation) async -> WeatherInfo? {
        if let cached, let at = cachedAt, Date().timeIntervalSince(cached.fetchedAt) < 30 * 60,
           at.distance(from: location) < 5_000 { return cached }
        let lat = (location.coordinate.latitude * 10).rounded() / 10
        let lng = (location.coordinate.longitude * 10).rounded() / 10
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(lat)), .init(name: "longitude", value: String(lng)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "4"), .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
        ]
        guard let url = c.url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return cached }
        let now = Date()
        var info = WeatherInfo(temp: raw.current.temperature_2m, code: raw.current.weather_code,
                               isDay: raw.current.is_day == 1, timeZone: raw.timezone)
        let hours = zip(raw.hourly.time.indices, raw.hourly.time).compactMap { i, t -> WeatherInfo.Hour? in
            let at = Date(timeIntervalSince1970: t)
            guard at > now.addingTimeInterval(-1800) else { return nil }
            return .init(at: at, temp: raw.hourly.temperature_2m[i], code: raw.hourly.weather_code[i], isDay: raw.hourly.is_day[i] == 1)
        }
        info.hours = Array(hours.prefix(12))
        info.days = raw.daily.time.indices.map {
            .init(date: Date(timeIntervalSince1970: raw.daily.time[$0]), high: raw.daily.temperature_2m_max[$0],
                  low: raw.daily.temperature_2m_min[$0], code: raw.daily.weather_code[$0])
        }
        info.high = info.days.first?.high
        info.low = info.days.first?.low
        info.place = try? await CLGeocoder().reverseGeocodeLocation(location).first.flatMap { $0.locality ?? $0.subAdministrativeArea ?? $0.administrativeArea }
        cached = info
        cachedAt = location
        return info
    }

    private struct Raw: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
        struct Hourly: Decodable { let time: [Double]; let temperature_2m: [Double]; let weather_code: [Int]; let is_day: [Int] }
        struct Daily: Decodable { let time: [Double]; let weather_code: [Int]; let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
        let timezone: String?
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }
}
