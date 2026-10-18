import SwiftUI
import WatchConnectivity
import WatchKit

/// Bond Touch Beyond for Apple Watch: a touch bar (tap and slide, recorded like the Bond
/// Touch More bar) and one-tap Touch Language meanings. The phone relays everything, so it
/// works with iCloud and original-app partners alike; the watch needs no account.
@main
struct BondWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @StateObject private var link = PhoneLink()
    @StateObject private var standIn = StandIn()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(link)
                .environmentObject(standIn)
                .onAppear { standIn.onChange = { [weak link] on in link?.reportStandIn(on) } }
        }
        // A partner's touch notification: drawn, and played on the wrist when it opens.
        WKNotificationScene(controller: TouchNotificationController.self, category: "TOUCH")
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
    var favourite = false
}

/// A touch in the watch's history: sent or received, a meaning, or a heartbeat.
struct WatchTouch: Identifiable, Equatable {
    let id: String
    let bondID: String
    let pattern: [Int]
    let generation: Int
    let startRGB: Int
    let endRGB: Int
    let sentAt: Date
    let mine: Bool
    var label: String?
    var bpm: Int?

    init?(_ d: [String: Any]) {
        guard let id = d["id"] as? String, let bond = d["bond"] as? String, let pattern = d["pattern"] as? [Int] else { return nil }
        self.id = id; bondID = bond; self.pattern = pattern
        generation = (d["gen"] as? Int) ?? 2
        startRGB = (d["start"] as? Int) ?? 0xFF2E74
        endRGB = (d["end"] as? Int) ?? startRGB
        sentAt = Date(timeIntervalSince1970: (d["at"] as? Double) ?? Date().timeIntervalSince1970)
        mine = (d["mine"] as? Bool) ?? false
        label = d["label"] as? String
        bpm = d["bpm"] as? Int
    }
}

/// Plays a touch on the watch's Taptic Engine, in its rhythm: a tap per press (and every
/// 150 ms through a long one); on a bar touch, the tap rises or falls with the slide; a
/// heartbeat taps on every beat.
enum WatchHaptics {
    static func play(_ t: WatchTouch) {
        var times: [(Double, WKHapticType)] = []
        if let bpm = t.bpm {
            let period = 60.0 / Double(min(max(bpm, 30), 220))
            var at = 0.0
            while at < 5 { times.append((at, .click)); times.append((at + 0.18, .directionUp)); at += period }
        } else if t.generation == 3 {
            var last: Int?
            var lastAt = -1.0
            for (i, sample) in t.pattern.prefix(TouchPattern.maxSamples).enumerated() {
                guard let f = TouchPattern.fingers(in: sample).first else { last = nil; continue }
                let at = Double(i) * Double(TouchPattern.sampleMs) / 1000
                guard at - lastAt >= 0.15 else { continue }
                let type: WKHapticType = last.map { f > $0 ? .directionUp : (f < $0 ? .directionDown : .click) } ?? .click
                times.append((at, type)); last = f; lastAt = at
            }
        } else {
            var at = 0.0
            for (i, ms) in t.pattern.enumerated() {
                let d = Double(max(ms, 0)) / 1000
                if i % 2 == 0 {
                    var x = 0.0
                    repeat { times.append((at + x, .click)); x += 0.15 } while x < d
                }
                at += d
                if at > 10 { break }
            }
        }
        for (at, type) in times {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { WKInterfaceDevice.current().play(type) }
        }
    }
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
    /// Recent touches per partner, newest last.
    @Published var history: [String: [WatchTouch]] = [:]

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
        var msg: [String: Any] = ["type": "touch", "bond": bond, "pattern": m.pattern, "name": m.name,
                                  "gen": m.generation, "start": m.startRGB, "end": m.endRGB]
        if let sid = m.serverID { msg["meaningId"] = sid }
        send(msg)
        lastSent = Date()
        WKInterfaceDevice.current().play(.success)
    }

    /// Tells the phone the watch is (or isn't) standing in for the bracelet.
    func reportStandIn(_ on: Bool) {
        send(["type": "standIn", "on": on])
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
                                    serverID: m["meaningId"] as? String, favourite: (m["fav"] as? Bool) ?? false)
            }
        }
        var history: [String: [WatchTouch]] = [:]
        for (bond, list) in (context["history"] as? [String: [[String: Any]]]) ?? [:] {
            history[bond] = list.compactMap(WatchTouch.init)
        }
        DispatchQueue.main.async {
            self.partners = partners
            self.meanings = meanings
            // Keep touches received since the phone last sent its context.
            for (bond, list) in history {
                let known = Set(list.map(\.id))
                self.history[bond] = list + (self.history[bond] ?? []).filter { !known.contains($0.id) && $0.sentAt > (list.last?.sentAt ?? .distantPast) }
            }
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

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { received(message) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { received(userInfo) }

    /// A touch the phone just played: play it here too (if it's fresh) and list it.
    private func received(_ message: [String: Any]) {
        guard message["type"] as? String == "received", let touch = WatchTouch(message) else { return }
        DispatchQueue.main.async {
            var list = self.history[touch.bondID] ?? []
            guard !list.contains(where: { $0.id == touch.id }) else { return }
            list.append(touch)
            self.history[touch.bondID] = Array(list.suffix(30))
            if Date().timeIntervalSince(touch.sentAt) < 120 { WatchHaptics.play(touch) }
        }
    }
}
