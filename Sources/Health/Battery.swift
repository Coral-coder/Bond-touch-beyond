import Foundation
import HealthKit

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

    var needsCare: Bool { level == "stressed" || level == "overwhelmed" }
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

    private let store = HKHealthStore()
    private let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    private let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
    private let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!

    init() {
        if let data = UserDefaults.standard.data(forKey: "moodEntries"),
           let list = try? JSONDecoder().decode([MoodEntry].self, from: data) { entries = list }
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

    /// Reads the body side from Health (asks for access the first time).
    func refresh() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: [], read: [hrvType, rhrType, sleepType])
        let ms = HKUnit.secondUnit(with: .milli)
        let monthAgo = Date().addingTimeInterval(-30 * 86_400), dayAgo = Date().addingTimeInterval(-36 * 3600)
        let hrvMonth = await quantities(hrvType, since: monthAgo, unit: ms)
        let hrvRecent = hrvMonth.filter { $0.0 > dayAgo }.map(\.1)
        let rhrMonth = await quantities(rhrType, since: monthAgo, unit: HKUnit.count().unitDivided(by: .minute()))
        let sleep = await lastNightSleep()

        hrv = hrvRecent.isEmpty ? nil : hrvRecent.reduce(0, +) / Double(hrvRecent.count)
        hrvBaseline = Self.median(hrvMonth.map(\.1))
        let dayStart = Date().addingTimeInterval(-24 * 3600)
        if let base = hrvBaseline, base > 0 {
            series = hrvMonth.filter { $0.0 > dayStart }.map { (at: $0.0, hrv: $0.1, stress: Self.stress(hrv: $0.1, baseline: base)) }
        }
        restingHR = rhrMonth.last?.1
        sleepHours = sleep

        var score = 60.0
        if let h = hrv, let base = hrvBaseline, base > 0 { score += (h / base - 1) * 80 }
        if let r = restingHR, let rBase = Self.median(rhrMonth.map(\.1)), rBase > 0 { score -= (r / rBase - 1) * 120 }
        if let s = sleep { score += (s - 7) * 6 }
        bodyBattery = (hrv == nil && sleep == nil) ? nil : Int(min(100, max(3, score)).rounded())
    }

    private func quantities(_ type: HKQuantityType, since: Date, unit: HKUnit) async -> [(Date, Double)] {
        await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil),
                                  limit: 500, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, s, _ in
                cont.resume(returning: (s as? [HKQuantitySample])?.map { ($0.endDate, $0.quantity.doubleValue(for: unit)) } ?? [])
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
