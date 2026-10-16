import Foundation
import HealthKit

/// Reads the user's heart rate from HealthKit (written by Apple Watch) and streams new
/// BPM values as they arrive. Used to send a live heartbeat to the partner's bracelet.
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
        let query = HKAnchoredObjectQuery(
            type: hrType, predicate: nil, anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.handle(samples: samples, newAnchor: newAnchor)
        }
        query.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.handle(samples: samples, newAnchor: newAnchor)
        }
        store.execute(query)
        anchoredQuery = query
        // Keep delivering while backgrounded so a shared heartbeat doesn't stall.
        store.enableBackgroundDelivery(for: hrType, frequency: .immediate) { _, _ in }
    }

    func stop() {
        if let q = anchoredQuery { store.stop(q); anchoredQuery = nil }
    }

    private func handle(samples: [HKSample]?, newAnchor: HKQueryAnchor?) {
        anchor = newAnchor
        guard let latest = (samples as? [HKQuantitySample])?
            .max(by: { $0.endDate < $1.endDate }) else { return }
        let bpm = Int(latest.quantity.doubleValue(for: unit).rounded())
        guard bpm > 0 else { return }
        Task { @MainActor in
            self.currentBPM = bpm
            self.onBPM?(bpm)
        }
    }
}
