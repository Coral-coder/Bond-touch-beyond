import Foundation
import HealthKit
import UIKit

/// How you're feeling, as shared with your partners (inside your sealed status snapshot).
/// It updates quietly; partners only get a notification when you're stressed or overwhelmed.
struct MoodShare: Codable, Equatable {
    var emoji: String
    var label: String
    /// 0–100: your personal battery (body + how you say you feel).
    var battery: Int
    /// "calm", "ok", "low", "stressed" or "overwhelmed".
    var level: String
    var at: Date
    /// The last 24 hours: [time (s since 1970), HRV (ms), stress 0–100] per Health reading.
    var series: [[Double]]? = nil
    /// Heart rate over the same day: [time (s since 1970), bpm], one point per 10 minutes.
    var heartRate: [[Double]]? = nil

    var needsCare: Bool { level == "stressed" || level == "overwhelmed" }

    /// Demo mode: 24 hours of HRV (every 90 min) and heart rate (every 10 min) up to `end`.
    static func demoDay(end: Date, seed: Double) -> (series: [[Double]], heartRate: [[Double]]) {
        let t0 = end.timeIntervalSince1970 - 24 * 3600
        let series = (0...16).map { i -> [Double] in
            let t = t0 + Double(i) * 5400
            let hrv = 46 + 12 * sin(Double(i) * 0.7 + seed) + 5 * sin(Double(i) * 1.9 + seed * 2)
            return [t, hrv.rounded(), max(5, min(95, 50 - (hrv / 46 - 1) * 90)).rounded()]
        }
        let heartRate = (0..<144).map { i -> [Double] in
            let t = t0 + Double(i) * 600
            let hour = (t / 3600).truncatingRemainder(dividingBy: 24)
            let asleep = hour < 6 || hour > 23
            return [t, ((asleep ? 56 : 72) + 9 * sin(Double(i) * 0.21 + seed) + 4 * sin(Double(i) * 0.9)).rounded()]
        }
        return (series, heartRate)
    }
    var stress: Int { 100 - battery }
}

/// Stress as a face, from relaxed to overwhelmed (0–100).
enum Stress {
    static let faces: [(limit: Int, emoji: String, label: String)] = [
        (15, "😌", "Relaxed"), (30, "🙂", "Calm"), (45, "😐", "Steady"), (60, "😕", "A bit tense"),
        (75, "😟", "Stressed"), (90, "😣", "Very stressed"), (101, "😵‍💫", "Overwhelmed"),
    ]
    static func face(_ stress: Int) -> (emoji: String, label: String) {
        let f = faces.first { stress < $0.limit } ?? faces[faces.count - 1]
        return (f.emoji, f.label)
    }
}

/// One mood you logged (kept on this phone; only the latest is shared, never the note).
struct MoodEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var at = Date()
    var emoji: String
    var label: String
    var level: String
    /// 0–100, how much energy you said you have.
    var energy: Int
    var note: String = ""
    var battery: Int
}

/// The moods to pick from.
enum Moods {
    static let all: [(emoji: String, label: String, level: String)] = [
        ("🥰", "Loved", "calm"), ("😌", "Calm", "calm"), ("🙂", "Good", "ok"), ("🤩", "Excited", "ok"),
        ("😴", "Tired", "low"), ("😕", "Meh", "low"), ("😢", "Sad", "low"), ("😟", "Anxious", "stressed"),
        ("😤", "Frustrated", "stressed"), ("😣", "Stressed", "stressed"), ("😵‍💫", "Overwhelmed", "overwhelmed"),
    ]
}

/// Your personal battery: from Apple Health — heart-rate variability (higher than your usual
/// means rested, lower means strained), resting heart rate and last night's sleep — blended
/// with the energy you log yourself. Read on this phone only.
@MainActor
final class BatteryService: ObservableObject {
    @Published private(set) var bodyBattery: Int?
    @Published private(set) var hrv: Double?
    @Published private(set) var hrvBaseline: Double?
    @Published private(set) var sleepHours: Double?
    @Published private(set) var restingHR: Double?
    @Published private(set) var entries: [MoodEntry] = []
    /// HRV readings over the last 24 hours, with the stress each one suggests.
    @Published private(set) var series: [(at: Date, hrv: Double, stress: Double)] = []
    /// Heart rate over the same day, averaged per 10 minutes.
    @Published private(set) var heartRate: [(at: Date, bpm: Double)] = []

    private let store = HKHealthStore()
    private let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    private let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
    private let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
    private let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

    /// When Health last gave readings (nil until it has).
    @Published private(set) var readAt: Date?

    init() {
        if let data = UserDefaults.standard.data(forKey: "moodEntries"),
           let list = try? JSONDecoder().decode([MoodEntry].self, from: data) { entries = list }
        loadCache()
    }

    /// The last good Health reading, kept across launches: Health is locked while the phone
    /// is, so a launch in the background (after an update, or from a push) reads nothing —
    /// that mustn't blank what partners see.
    private struct Cache: Codable {
        var bodyBattery: Int?, hrv: Double?, hrvBaseline: Double?, sleepHours: Double?, restingHR: Double?
        var series: [[Double]], readAt: Date
        var heartRate: [[Double]]? = nil
    }
    private static let cacheKey = "healthCache"

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let c = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        bodyBattery = c.bodyBattery; hrv = c.hrv; hrvBaseline = c.hrvBaseline
        sleepHours = c.sleepHours; restingHR = c.restingHR; readAt = c.readAt
        series = c.series.compactMap { $0.count == 3 ? (at: Date(timeIntervalSince1970: $0[0]), hrv: $0[1], stress: $0[2]) : nil }
        heartRate = (c.heartRate ?? []).compactMap { $0.count == 2 ? (at: Date(timeIntervalSince1970: $0[0]), bpm: $0[1]) : nil }
    }

    private func saveCache() {
        let c = Cache(bodyBattery: bodyBattery, hrv: hrv, hrvBaseline: hrvBaseline, sleepHours: sleepHours,
                      restingHR: restingHR, series: series.map { [$0.at.timeIntervalSince1970, $0.hrv, $0.stress] },
                      readAt: readAt ?? Date(),
                      heartRate: heartRate.map { [$0.at.timeIntervalSince1970, $0.bpm] })
        if let data = try? JSONEncoder().encode(c) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
    }

    /// Demo mode (screenshots): a believable day of readings ending now.
    func loadDemo() {
        let day = MoodShare.demoDay(end: Date(), seed: 1)
        series = day.series.map { (at: Date(timeIntervalSince1970: $0[0]), hrv: $0[1], stress: $0[2]) }
        heartRate = day.heartRate.map { (at: Date(timeIntervalSince1970: $0[0]), bpm: $0[1]) }
        hrv = 48; hrvBaseline = 44; restingHR = 58; sleepHours = 7.4; bodyBattery = 72; readAt = Date()
        entries = [MoodEntry(at: Date().addingTimeInterval(-3 * 3600), emoji: "🙂", label: "Good", level: "ok", energy: 70, battery: 72)]
    }

    /// The battery to show and share: your latest log (if from the last 12 hours) blended
    /// with your body's reading.
    var battery: Int? {
        let recent = entries.last.flatMap { Date().timeIntervalSince($0.at) < 12 * 3600 ? $0 : nil }
        switch (bodyBattery, recent) {
        case let (body?, log?): return Int((Double(body) * 0.5 + Double(log.energy) * 0.5).rounded())
        case let (body?, nil): return body
        case let (nil, log?): return log.energy
        default: return nil
        }
    }

    func log(_ entry: MoodEntry) {
        entries.append(entry)
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: "moodEntries") }
    }

    /// Reads the body side from Health (asks for access the first time). Returns false when
    /// Health couldn't be read (phone locked) — the last reading then stays as it was.
    @discardableResult
    func refresh() async -> Bool {
        // Demo mode runs unsigned in the simulator, without the HealthKit entitlement, where
        // asking for access ends the app.
        guard HKHealthStore.isHealthDataAvailable(), !ProcessInfo.processInfo.arguments.contains("-demo") else { return false }
        // Health's data is encrypted while the phone is locked: every query comes back empty.
        guard UIApplication.shared.isProtectedDataAvailable else { return false }
        try? await store.requestAuthorization(toShare: [], read: [hrvType, rhrType, sleepType, hrType])
        let ms = HKUnit.secondUnit(with: .milli)
        let monthAgo = Date().addingTimeInterval(-30 * 86_400), dayAgo = Date().addingTimeInterval(-36 * 3600)
        let hrvMonth = await quantities(hrvType, since: monthAgo, unit: ms)
        // The last day of readings — ending now, or at the newest reading when the watch hasn't
        // been worn since — so there's always a last report to show and share.
        let hrvEnd = hrvMonth.last?.0 ?? Date()
        let hrvRecent = hrvMonth.filter { $0.0 > min(dayAgo, hrvEnd.addingTimeInterval(-36 * 3600)) }.map(\.1)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hrRaw = await quantities(hrType, since: Date().addingTimeInterval(-7 * 86_400), unit: bpm)
        let rhrMonth = await quantities(rhrType, since: monthAgo, unit: HKUnit.count().unitDivided(by: .minute()))
        let sleep = await lastNightSleep()
        // Nothing at all from a month of Health (locked mid-read, or no access): keep the last
        // reading rather than wiping it.
        if hrvMonth.isEmpty && rhrMonth.isEmpty && hrRaw.isEmpty && sleep == nil && readAt != nil { return false }

        hrv = hrvRecent.isEmpty ? nil : hrvRecent.reduce(0, +) / Double(hrvRecent.count)
        hrvBaseline = Self.median(hrvMonth.map(\.1))
        let dayStart = min(Date(), hrvEnd).addingTimeInterval(-24 * 3600)
        if let base = hrvBaseline, base > 0 {
            series = hrvMonth.filter { $0.0 > dayStart }.map { (at: $0.0, hrv: $0.1, stress: Self.stress(hrv: $0.1, baseline: base)) }
        }
        if let hrLast = hrRaw.last?.0 {
            heartRate = Self.tenMinuteAverages(hrRaw.filter { $0.0 > min(Date(), hrLast).addingTimeInterval(-24 * 3600) })
        }
        restingHR = rhrMonth.last?.1
        sleepHours = sleep

        var score = 60.0
        if let h = hrv, let base = hrvBaseline, base > 0 { score += (h / base - 1) * 80 }
        if let r = restingHR, let rBase = Self.median(rhrMonth.map(\.1)), rBase > 0 { score -= (r / rBase - 1) * 120 }
        if let s = sleep { score += (s - 7) * 6 }
        bodyBattery = (hrv == nil && sleep == nil) ? nil : Int(min(100, max(3, score)).rounded())
        readAt = Date()
        saveCache()
        return true
    }

    /// Heart-rate samples (a watch logs one every few seconds in a workout) as one average per
    /// 10 minutes: at most 144 points a day.
    private static func tenMinuteAverages(_ samples: [(Date, Double)]) -> [(at: Date, bpm: Double)] {
        var buckets: [Int: (sum: Double, count: Int)] = [:]
        for (at, v) in samples {
            let key = Int(at.timeIntervalSince1970 / 600)
            buckets[key, default: (0, 0)].sum += v
            buckets[key, default: (0, 0)].count += 1
        }
        return buckets.keys.sorted().map { key in
            let b = buckets[key]!
            return (at: Date(timeIntervalSince1970: Double(key) * 600 + 300), bpm: (b.sum / Double(b.count)).rounded())
        }
    }

    /// When the newest Health reading (HRV) was taken: how you tell "not wearing the watch"
    /// from "nothing to share".
    var lastReadingAt: Date? { series.last?.at }

    private func quantities(_ type: HKQuantityType, since: Date, unit: HKUnit) async -> [(Date, Double)] {
        await withCheckedContinuation { cont in
            // Newest first, so a busy month (an Apple Watch can log well over the limit) cuts off
            // the oldest readings, never the last day's; then back into time order.
            let q = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil),
                                  limit: 3000, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, s, _ in
                cont.resume(returning: (s as? [HKQuantitySample])?.reversed().map { ($0.endDate, $0.quantity.doubleValue(for: unit)) } ?? [])
            }
            store.execute(q)
        }
    }

    private func lastNightSleep() async -> Double? {
        await withCheckedContinuation { cont in
            let since = Date().addingTimeInterval(-20 * 3600)
            let q = HKSampleQuery(sampleType: sleepType, predicate: HKQuery.predicateForSamples(withStart: since, end: nil),
                                  limit: 300, sortDescriptors: nil) { _, s, _ in
                let asleep = (s as? [HKCategorySample])?.filter {
                    $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue && $0.value != HKCategoryValueSleepAnalysis.awake.rawValue
                } ?? []
                let secs = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: asleep.isEmpty ? nil : secs / 3600)
            }
            store.execute(q)
        }
    }

    /// Lower HRV than your usual reads as more stress (50 = your usual).
    static func stress(hrv: Double, baseline: Double) -> Double {
        min(100, max(0, 50 - (hrv / baseline - 1) * 90))
    }

    /// Stress now (0–100): the inverse of the battery.
    var stress: Int? { battery.map { 100 - $0 } }

    private static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted()
        return s[s.count / 2]
    }
}
