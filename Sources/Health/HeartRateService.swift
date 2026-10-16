import Foundation
import HealthKit

/// Reads the user's heart rate from HealthKit (written by Apple Watch). The app reads the
/// latest sample when the user presses Send my heartbeat; nothing streams in between.
@MainActor
final class HeartRateService: ObservableObject {
    @Published private(set) var currentBPM: Int?
    @Published private(set) var authorized = false
    @Published private(set) var available = HKHealthStore.isHealthDataAvailable()

    private let store = HKHealthStore()
    private let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let unit = HKUnit.count().unitDivided(by: .minute())
    private var anchor: HKQueryAnchor?
    private var anchoredQuery: HKAnchoredObjectQuery?

    /// Callback fired whenever a new BPM is read (used to relay to the partner).
    var onBPM: ((Int) -> Void)?

    func requestAuthorization() async {
        guard available else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [hrType])
            authorized = true
        } catch {
            authorized = false
        }
    }

    /// Starts streaming heart-rate samples. New samples arrive as the Watch records them.
    func start() {
        guard available, anchoredQuery == nil else { return }
        let unit = self.unit   // capture a local so the background callback touches no isolated state
        // HealthKit calls this on a background queue, so it must not touch main-actor state
        // directly; it computes the BPM and hops to the main actor to publish it.
        let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void
            = { [weak self] _, samples, _, newAnchor, _ in
                let bpm = (samples as? [HKQuantitySample])?
                    .max(by: { $0.endDate < $1.endDate })?
                    .quantity.doubleValue(for: unit)
                Task { @MainActor in
                    guard let self else { return }
                    self.anchor = newAnchor
                    if let bpm, bpm > 0 {
                        let value = Int(bpm.rounded())
                        self.currentBPM = value
                        self.onBPM?(value)
                    }
                }
            }
        let query = HKAnchoredObjectQuery(type: hrType, predicate: nil, anchor: anchor,
                                          limit: HKObjectQueryNoLimit, resultsHandler: handler)
        query.updateHandler = handler
        store.execute(query)
        anchoredQuery = query
        // Keep delivering while backgrounded so a shared heartbeat doesn't stall.
        store.enableBackgroundDelivery(for: hrType, frequency: .immediate) { _, _ in }
    }

    func stop() {
        if let q = anchoredQuery { store.stop(q); anchoredQuery = nil }
    }

    /// The most recent heart rate recorded in the last 15 minutes, or nil.
    func latestBPM() async -> Int? {
        guard available else { return nil }
        let unit = self.unit
        let since = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-15 * 60), end: nil)
        let bpm: Int? = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: hrType, predicate: since, limit: 1,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: v.map { Int($0.rounded()) })
            }
            store.execute(q)
        }
        if let bpm { currentBPM = bpm }
        return bpm
    }
}
