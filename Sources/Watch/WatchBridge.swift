import Combine
import Foundation
import HealthKit
import WatchConnectivity

/// The phone's side of the Apple Watch link: publishes partners, the selected partner, each
/// partner's Touch Language and the touch window in the application context, and relays
/// touches and selections from the watch through the normal send path (iCloud or the
/// original backend).
final class WatchBridge: NSObject, WCSessionDelegate {
    weak var model: AppModel?
    private var cancellables: Set<AnyCancellable> = []

    @MainActor
    func start(_ model: AppModel) {
        guard WCSession.isSupported() else { return }
        self.model = model
        WCSession.default.delegate = self
        WCSession.default.activate()
        Publishers.CombineLatest4(model.$cloudPartners, model.$legacyPartners,
                                  model.$selectedPartnerID, model.$legacyMeanings)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.push() } }
            .store(in: &cancellables)
    }

    @MainActor
    func push() {
        guard let model, WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let partners: [[String: Any]] = model.partners.map {
            ["id": $0.id, "name": $0.displayName, "color": $0.colorRGB, "online": $0.online]
        }
        var meanings: [String: [[String: Any]]] = [:]
        for p in model.partners {
            let list = model.meanings(for: p.bond)
            // Favourites first, as the original watch app.
            let ordered = list.filter { $0.favourite == true } + list.filter { $0.favourite != true }
            meanings[p.id] = ordered.map {
                var d: [String: Any] = ["name": $0.label, "pattern": $0.pattern, "gen": $0.touchGeneration,
                                        "start": $0.colorRGB, "end": $0.endColorRGB,
                                        "fav": $0.favourite == true]
                if let sid = $0.serverID { d["meaningId"] = sid }   // so it lights the partner's bracelet
                return d
            }
        }
        // Recent touches with each partner, for the watch's history page.
        var history: [String: [[String: Any]]] = [:]
        for p in model.partners {
            history[p.id] = model.history.filter { $0.bondID == p.id }.suffix(15).map { Self.encode($0, model: model) }
        }
        var context: [String: Any] = ["partners": partners, "meanings": meanings, "history": history,
                                      "window": model.store.touchWindowSeconds]
        if let s = model.selectedPartnerID { context["selected"] = s }
        try? WCSession.default.updateApplicationContext(context)
    }

    /// Whether there's a watch with the app to stand in for the bracelet.
    var watchAvailable: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
            && WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
    }

    private let health = HKHealthStore()

    /// Wakes the watch app into Stand-in mode (it plays touches on the wrist), even with the
    /// watch app closed: HealthKit starts its workout session from the phone.
    func startWatchStandIn() {
        guard watchAvailable, HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .unknown
        health.startWatchApp(with: config) { ok, error in
            NetLog.shared.record(ok ? .ok : .fail, ok ? "Woke the watch to stand in for the bracelet"
                                                      : "Couldn't wake the watch", error?.localizedDescription ?? "")
        }
    }

    /// Tells the watch to stop standing in (the bracelet is back).
    func stopWatchStandIn() {
        guard watchAvailable else { return }
        let message: [String: Any] = ["type": "standInSet", "on": false]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in WCSession.default.transferUserInfo(message) }
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    /// A touch the phone just played: the watch plays it too (haptics) and lists it.
    @MainActor
    func forward(_ touch: TouchMessage) {
        guard let model, WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        var message = Self.encode(touch, model: model)
        message["type"] = "received"
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in WCSession.default.transferUserInfo(message) }
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    @MainActor
    private static func encode(_ t: TouchMessage, model: AppModel) -> [String: Any] {
        let mine = t.senderID == model.myUserID || t.senderID == ChatMessage.legacySelf
        var d: [String: Any] = ["id": t.id.uuidString, "bond": t.bondID, "pattern": t.pattern, "gen": t.generation,
                                "start": t.colorRGB, "end": t.endColorRGB, "at": t.sentAt.timeIntervalSince1970,
                                "mine": mine]
        if let label = t.meaningLabel { d["label"] = label }
        if let bpm = t.heartbeatBPM { d["bpm"] = bpm }
        return d
    }

    private func handle(_ message: [String: Any]) {
        Task { @MainActor in
            guard let model else { return }
            switch message["type"] as? String {
            case "touch":
                guard let bond = message["bond"] as? String, let pattern = message["pattern"] as? [Int] else { return }
                let start = (message["start"] as? Int) ?? model.store.profile.colorRGB
                let end = message["end"] as? Int ?? start
                let gen = (message["gen"] as? Int) ?? 3
                // A saved meaning carries its id, so send it as a meaning (lights the partner's band).
                if let sid = message["meaningId"] as? String, !sid.isEmpty {
                    let m = TouchMeaning(label: (message["name"] as? String) ?? "Touch", emoji: "", colorRGB: start,
                                         endColorRGB: end, pattern: pattern, serverID: sid, generation: gen)
                    await model.sendMeaning(m, toBondID: bond)
                } else if let name = message["name"] as? String,
                          let p = model.partners.first(where: { $0.id == bond }),
                          let m = model.meanings(for: p.bond).first(where: { $0.label == name }) {
                    // An iCloud meaning: sent as itself, labelled.
                    await model.sendMeaning(m, toBondID: bond)
                } else {
                    await model.sendTouch(pattern: pattern, generation: gen,
                                          colorRGB: start, endColorRGB: end, toBondID: bond)
                }
            case "standIn":
                model.watchStandIn = (message["on"] as? Bool) ?? false
                NetLog.shared.log(.recv, model.watchStandIn ? "Apple Watch is standing in for the bracelet"
                                                            : "Apple Watch stand-in off")
            case "select":
                if let bond = message["bond"] as? String, model.partners.contains(where: { $0.id == bond }) {
                    model.selectedPartnerID = bond
                }
            default:
                break
            }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        Task { @MainActor in self.push() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { handle(userInfo) }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.push() } }
}
