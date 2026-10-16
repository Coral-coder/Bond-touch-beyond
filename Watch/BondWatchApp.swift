import SwiftUI
import WatchConnectivity
import WatchKit

/// Bond Touch Beyond for Apple Watch: a touch bar (tap and slide, recorded like the Bond
/// Touch More bar) and one-tap Touch Language meanings. The phone relays everything, so it
/// works with iCloud and original-app partners alike; the watch needs no account.
@main
struct BondWatchApp: App {
    @StateObject private var link = PhoneLink()

    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(link)
        }
    }
}

struct WatchPartner: Identifiable, Equatable {
    let id: String
    let name: String
    let colorRGB: Int
    let online: Bool
}

struct WatchMeaning: Identifiable, Equatable {
    var id: String { name + "\(pattern.count)" }
    let name: String
    let pattern: [Int]
    let generation: Int
    let startRGB: Int
    let endRGB: Int
    /// The meaning's id on the original backend (so it lights the partner's bracelet).
    var serverID: String? = nil
}

/// The watch's side of the phone link: receives partners, the selection and meanings in
/// the application context, and sends touches back (live when the phone is reachable,
/// otherwise queued and delivered when it is).
final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published var partners: [WatchPartner] = []
    @Published var selectedID: String?
    @Published var meanings: [String: [WatchMeaning]] = [:]
    @Published var windowSeconds: Double = 5
    @Published var lastSent: Date?

    var selected: WatchPartner? { partners.first { $0.id == selectedID } ?? partners.first }

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func sendTouch(pattern: [Int], generation: Int, startRGB: Int, endRGB: Int) {
        guard let bond = selected?.id else { return }
        send(["type": "touch", "bond": bond, "pattern": pattern, "gen": generation,
              "start": startRGB, "end": endRGB])
        lastSent = Date()
        WKInterfaceDevice.current().play(.success)
    }

    /// Sends a saved meaning (by id when it has one, so the partner's bracelet lights up).
    func sendMeaning(_ m: WatchMeaning) {
        guard let bond = selected?.id else { return }
        var msg: [String: Any] = ["type": "touch", "bond": bond, "pattern": m.pattern,
                                  "gen": m.generation, "start": m.startRGB, "end": m.endRGB]
        if let sid = m.serverID { msg["meaningId"] = sid }
        send(msg)
        lastSent = Date()
        WKInterfaceDevice.current().play(.success)
    }

    func select(_ id: String) {
        selectedID = id
        send(["type": "select", "bond": id])
    }

    private func send(_ message: [String: Any]) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in session.transferUserInfo(message) }
        } else {
            session.transferUserInfo(message)
        }
    }

    private func apply(_ context: [String: Any]) {
        let partners = ((context["partners"] as? [[String: Any]]) ?? []).compactMap { p -> WatchPartner? in
            guard let id = p["id"] as? String else { return nil }
            return WatchPartner(id: id, name: (p["name"] as? String) ?? "Partner",
                                colorRGB: (p["color"] as? Int) ?? 0xFF4081, online: (p["online"] as? Bool) ?? false)
        }
        var meanings: [String: [WatchMeaning]] = [:]
        for (bond, list) in (context["meanings"] as? [String: [[String: Any]]]) ?? [:] {
            meanings[bond] = list.compactMap { m in
                guard let name = m["name"] as? String, let pattern = m["pattern"] as? [Int] else { return nil }
                return WatchMeaning(name: name, pattern: pattern, generation: (m["gen"] as? Int) ?? 2,
                                    startRGB: (m["start"] as? Int) ?? 0xFF2E74, endRGB: (m["end"] as? Int) ?? 0xBE5BFF,
                                    serverID: m["meaningId"] as? String)
            }
        }
        DispatchQueue.main.async {
            self.partners = partners
            self.meanings = meanings
            if let s = context["selected"] as? String { self.selectedID = s }
            if let w = context["window"] as? Double { self.windowSeconds = w }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}
