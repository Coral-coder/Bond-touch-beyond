import CoreLocation
import Foundation
import WeatherKit

/// Looks the weather up with WeatherKit for a place, at most every 30 minutes per place
/// (moving more than 5 km counts as a new place).
actor WeatherFetcher {
    static let shared = WeatherFetcher()
    private var cache: [String: (info: WeatherInfo, at: CLLocation)] = [:]

    func weather(at location: CLLocation, key: String) async -> WeatherInfo? {
        if let c = cache[key], Date().timeIntervalSince(c.info.fetchedAt) < 30 * 60, c.at.distance(from: location) < 5_000 {
            return c.info
        }
        do {
            let w = try await WeatherService.shared.weather(for: location)
            let now = Date()
            func c(_ m: Measurement<UnitTemperature>) -> Double { m.converted(to: .celsius).value }
            var info = WeatherInfo(temp: c(w.currentWeather.temperature), symbol: w.currentWeather.symbolName,
                                   summary: w.currentWeather.condition.description)
            info.hours = w.hourlyForecast.forecast.filter { $0.date > now.addingTimeInterval(-1800) }.prefix(12)
                .map { .init(at: $0.date, temp: c($0.temperature), symbol: $0.symbolName) }
            info.days = w.dailyForecast.forecast.prefix(4)
                .map { .init(date: $0.date, high: c($0.highTemperature), low: c($0.lowTemperature), symbol: $0.symbolName) }
            info.high = info.days.first?.high
            info.low = info.days.first?.low
            let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            info.place = mark?.locality ?? mark?.subAdministrativeArea ?? mark?.administrativeArea
            info.timeZone = mark?.timeZone?.identifier
            cache[key] = (info, location)
            return info
        } catch {
            await NetLog.shared.log(.fail, "Weather unavailable", error.localizedDescription)
            return cache[key]?.info
        }
    }
}
