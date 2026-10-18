import HealthKit
import SwiftUI
import WatchKit

/// Stand-in mode: the watch takes the bracelet's place. While it's on, the watch app keeps
/// running (as a workout session — the only way watchOS lets an app stay awake with the
/// screen off), so every touch the phone passes on plays on the wrist straight away, in its
/// own rhythm. The phone and the partner's phone are told, so pushes stay quiet and the
/// watch doesn't buzz twice. Costs watch battery while on.
final class StandIn: NSObject, ObservableObject, HKWorkoutSessionDelegate {
    @Published private(set) var on = false
    @Published var problem: String?
    var onChange: ((Bool) -> Void)?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?

    func toggle() { on ? stop() : start() }

    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { problem = "Not available on this watch."; return }
        store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: []) { [weak self] ok, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard ok else { self.problem = "Allow Health access to keep the watch awake."; return }
                let config = HKWorkoutConfiguration()
                config.activityType = .mindAndBody
                config.locationType = .unknown
                do {
                    let session = try HKWorkoutSession(healthStore: self.store, configuration: config)
                    session.delegate = self
                    session.startActivity(with: Date())
                    self.session = session
                    self.set(true)
                    WKInterfaceDevice.current().play(.start)
                } catch {
                    self.problem = "Couldn't start: \(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        session?.end()
        session = nil
        set(false)
        WKInterfaceDevice.current().play(.stop)
    }

    private func set(_ value: Bool) {
        problem = nil
        on = value
        onChange?(value)
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended || toState == .stopped {
            DispatchQueue.main.async { if self.on { self.session = nil; self.set(false) } }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.session = nil; self.set(false); self.problem = error.localizedDescription }
    }
}

/// The Stand-in page: one switch, and what it does.
struct WatchStandInView: View {
    @EnvironmentObject var link: PhoneLink
    @EnvironmentObject var standIn: StandIn

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchPartnerHeader()
                Button { standIn.toggle() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: standIn.on ? "applewatch.radiowaves.left.and.right" : "applewatch")
                            .font(.title2)
                        Text(standIn.on ? "Standing in" : "Stand-in mode").font(.system(.headline, design: .rounded))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .tint(standIn.on ? Color(rgb: 0x57C3BB) : .gray)
                Text(standIn.on ? "Touches play on your wrist the moment they arrive, like your bracelet."
                                : "Not wearing your bracelet? Turn this on and your watch plays every touch in its rhythm. Uses more battery.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let problem = standIn.problem {
                    Text(problem).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
            }
        }
    }
}
