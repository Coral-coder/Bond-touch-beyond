import CoreLocation
import Foundation

/// Looks the weather up for a place (Open-Meteo: free, no account or key; the position sent
/// is rounded to about 10 km), at most every 30 minutes per place — moving more than 5 km
/// counts as a new place.
actor WeatherFetcher {
    static let shared = WeatherFetcher()
    private var cache: [String: (info: WeatherInfo, at: CLLocation)] = [:]

    func weather(at location: CLLocation, key: String) async -> WeatherInfo? {
        if let c = cache[key], Date().timeIntervalSince(c.info.fetchedAt) < 30 * 60, c.at.distance(from: location) < 5_000 {
            return c.info
        }
        let lat = (location.coordinate.latitude * 10).rounded() / 10
        let lng = (location.coordinate.longitude * 10).rounded() / 10
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(lat)), .init(name: "longitude", value: String(lng)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "4"), .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
        ]
        guard let url = comps.url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return cache[key]?.info }
        let now = Date()
        var info = WeatherInfo(temp: raw.current.temperature_2m,
                               symbol: Self.symbol(raw.current.weather_code, isDay: raw.current.is_day == 1),
                               summary: Self.summary(raw.current.weather_code))
        info.timeZone = raw.timezone
        info.hours = raw.hourly.time.indices.compactMap { i -> WeatherInfo.Hour? in
            let at = Date(timeIntervalSince1970: raw.hourly.time[i])
            guard at > now.addingTimeInterval(-1800) else { return nil }
            return .init(at: at, temp: raw.hourly.temperature_2m[i],
                         symbol: Self.symbol(raw.hourly.weather_code[i], isDay: raw.hourly.is_day[i] == 1))
        }.prefix(12).map { $0 }
        info.days = raw.daily.time.indices.map {
            .init(date: Date(timeIntervalSince1970: raw.daily.time[$0]), high: raw.daily.temperature_2m_max[$0],
                  low: raw.daily.temperature_2m_min[$0], symbol: Self.symbol(raw.daily.weather_code[$0], isDay: true))
        }
        info.high = info.days.first?.high
        info.low = info.days.first?.low
        let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        info.place = mark?.locality ?? mark?.subAdministrativeArea ?? mark?.administrativeArea
        cache[key] = (info, location)
        return info
    }

    /// An SF Symbol for a WMO weather code.
    static func symbol(_ code: Int, isDay: Bool) -> String {
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

    static func summary(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow Showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "—"
        }
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
