import Combine
import Foundation
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
            let list = p.bond.legacy ? (model.legacyMeanings[p.id] ?? []) : model.store.meanings
            meanings[p.id] = list.map {
                ["name": $0.label, "pattern": $0.pattern, "gen": $0.touchGeneration,
                 "start": $0.colorRGB, "end": $0.endColorRGB]
            }
        }
        var context: [String: Any] = ["partners": partners, "meanings": meanings,
                                      "window": model.store.touchWindowSeconds]
        if let s = model.selectedPartnerID { context["selected"] = s }
        try? WCSession.default.updateApplicationContext(context)
    }

    private func handle(_ message: [String: Any]) {
        Task { @MainActor in
            guard let model else { return }
            switch message["type"] as? String {
            case "touch":
                guard let bond = message["bond"] as? String, let pattern = message["pattern"] as? [Int] else { return }
                await model.sendTouch(pattern: pattern, generation: (message["gen"] as? Int) ?? 3,
                                      colorRGB: (message["start"] as? Int) ?? model.store.profile.colorRGB,
                                      endColorRGB: message["end"] as? Int, toBondID: bond)
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
