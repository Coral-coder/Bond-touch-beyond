import SwiftUI
import WatchConnectivity
import WatchKit

/// Bond Touch Beyond for Apple Watch: a touch bar (tap and slide, recorded like the Bond
/// Touch More bar) and one-tap Touch Language meanings. The phone relays everything, so it
/// works with iCloud and original-app partners alike; the watch needs no account.
@main
struct BondWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @StateObject private var link = PhoneLink.shared
    @StateObject private var standIn = StandIn.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(link)
                .environmentObject(standIn)
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

/// Plays a touch on the watch's Taptic Engine, in its rhythm: one firm tap per press (a long
/// press taps through its length; a slide taps along it; a heartbeat taps every beat).
///
/// Apple only lets watch apps use its preset haptics, and each comes with a short system
/// tone unless the watch is on Silent. So every tap uses the same firm, single-tap type
/// (`.start`) — no rising/falling "direction" tones, which turned a slide into a run of
/// bleep-boops — and taps are spaced so they stay distinct and strong.
enum WatchHaptics {
    private static let tap: WKHapticType = .start
    private static let minGap = 0.28

    /// Touches already played (partner + send time), so a touch relayed to the app and then
    /// opened as a notification doesn't play twice. `again` (replay buttons) always plays.
    private static var played: [String: Date] = [:]

    static func play(_ t: WatchTouch, again: Bool = false) {
        guard firstTime(t) || again else { return }
        WatchVibration.play(t)   // silent vibration first; Apple's taps only as a last resort
    }

    /// A touch notification on the wrist: one firm silent buzz, not the rhythm (the
    /// notification's own sound is the chime). Nothing if the touch already played here.
    static func alert(_ t: WatchTouch) {
        guard firstTime(t) else { return }
        WatchVibration.pulse()
    }

    /// Marks the touch played; false if it already was in the last minute.
    private static func firstTime(_ t: WatchTouch) -> Bool {
        let key = "\(t.bondID)|\(Int(t.sentAt.timeIntervalSince1970))"
        played = played.filter { Date().timeIntervalSince($0.value) < 60 }
        let fresh = played[key] == nil
        played[key] = Date()
        return fresh
    }

    /// Apple's public firm taps (each with a system tone unless the watch is on Silent).
    static func playAppleTaps(_ t: WatchTouch) {
        var times: [Double] = []
        if let bpm = t.bpm {
            let period = 60.0 / Double(min(max(bpm, 30), 220))
            var at = 0.0
            while at < 5 { times.append(at); at += period }
        } else if t.generation == 3 {
            for (i, sample) in t.pattern.prefix(TouchPattern.maxSamples).enumerated()
            where !TouchPattern.fingers(in: sample).isEmpty {
                times.append(Double(i) * Double(TouchPattern.sampleMs) / 1000)
            }
        } else {
            var at = 0.0
            for (i, ms) in t.pattern.enumerated() {
                let d = Double(max(ms, 0)) / 1000
                if i % 2 == 0 {
                    var x = 0.0
                    repeat { times.append(at + x); x += minGap } while x < d
                }
                at += d
                if at > 10 { break }
            }
        }
        var last = -1.0
        for at in times where at - last >= minGap {
            last = at
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { WKInterfaceDevice.current().play(tap) }
        }
    }
}

/// The watch's side of the phone link: receives partners, the selection and meanings in
/// the application context, and sends touches back (live when the phone is reachable,
/// otherwise queued and delivered when it is).
final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
    /// One for the app, so a background launch (Stand-in started by the phone) has it too.
    static let shared = PhoneLink()

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
        WatchVibration.tick()   // silent confirmation (Apple's .success plays a tone)
    }

    /// Sends a saved meaning (by id when it has one, so the partner's bracelet lights up).
    func sendMeaning(_ m: WatchMeaning) {
        guard let bond = selected?.id else { return }
        var msg: [String: Any] = ["type": "touch", "bond": bond, "pattern": m.pattern, "name": m.name,
                                  "gen": m.generation, "start": m.startRGB, "end": m.endRGB]
        if let sid = m.serverID { msg["meaningId"] = sid }
        send(msg)
        lastSent = Date()
        WatchVibration.tick()   // silent confirmation (Apple's .success plays a tone)
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

    /// A touch the phone just played: list it, and in Stand-in play it here in its rhythm (if
    /// it's fresh). Otherwise the touch notification buzzes once — no rhythm on top of it.
    /// Also the phone switching Stand-in off once the bracelet is back.
    private func received(_ message: [String: Any]) {
        if message["type"] as? String == "standInSet", (message["on"] as? Bool) == false {
            DispatchQueue.main.async { StandIn.shared.stop() }
            return
        }
        guard message["type"] as? String == "received", let touch = WatchTouch(message) else { return }
        DispatchQueue.main.async {
            var list = self.history[touch.bondID] ?? []
            guard !list.contains(where: { $0.id == touch.id }) else { return }
            list.append(touch)
            self.history[touch.bondID] = Array(list.suffix(30))
            if StandIn.shared.on, Date().timeIntervalSince(touch.sentAt) < 120 { WatchHaptics.play(touch) }
        }
    }
}
