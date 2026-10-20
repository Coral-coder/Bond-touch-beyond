import SwiftUI
import UIKit

/// Demo mode, for screenshots of every screen (launch argument `-demo`): sample partners,
/// touches, meanings, an Us space and weather, with no iCloud, Bluetooth, location or
/// permission prompts. `-demoTab <tab>` opens a tab, `-demoScreen <screen>` a sub-screen,
/// and `-appStyle` / `-homeLayout` (plain UserDefaults launch arguments) pick the look.
extension AppModel {
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static func demoArgument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `-demoScrollBottom`: a few seconds in, scroll every vertical scroll view to its end, so
    /// screenshots show what the last row looks like above the tab bar.
    static func scrollEverythingToBottomForDemo() {
        guard demoArgument("-demoScrollBottom") != nil else { return }
        for delay in [3.0, 5.5] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            func walk(_ v: UIView) {
                if let s = v as? UIScrollView, s.contentSize.height > s.bounds.height {
                    let bottom = s.contentSize.height + s.adjustedContentInset.bottom - s.bounds.height
                    s.setContentOffset(CGPoint(x: s.contentOffset.x, y: max(-s.adjustedContentInset.top, bottom)), animated: false)
                }
                v.subviews.forEach(walk)
            }
            for scene in UIApplication.shared.connectedScenes {
                (scene as? UIWindowScene)?.windows.forEach(walk)
            }
        } }
    }

    func loadDemo() {
        Self.scrollEverythingToBottomForDemo()
        var profile = store.profile
        profile.name = "Sam"
        profile.colorRGB = 0x57C3BB
        store.profile = profile

        let alexBond = Bond(id: "DEMOALEX", partnerName: "Alex", isOwner: true)
        var alex = Partner(bond: alexBond, colorRGB: 0xEC5A89, online: true, lastSeen: Date(),
                           latitude: 48.8566, longitude: 2.3522)
        alex.presence = PresenceInfo(online: true, lat: 48.8566, lng: 2.3522, locationAt: Date(), speed: 0,
                                     phoneBattery: 0.64, phoneCharging: false, bracelet: true, braceletBattery: 82)
        var jo = Partner(bond: Bond(id: "DEMOJO", partnerName: "Jo", isOwner: false), colorRGB: 0xECA94B, online: false,
                         lastSeen: Date().addingTimeInterval(-3600))
        jo.presence = PresenceInfo(online: false, bracelet: false)
        cloudPartners = [alex, jo]
        selectedPartnerID = alex.id

        let love = TouchMeaning(label: "Love you", emoji: "💗", colorRGB: 0xEC5A89, endColorRGB: 0xB173DF,
                                pattern: [140, 120, 140, 120, 520], generation: 2)
        let miss = TouchMeaning(label: "Miss you", emoji: "🥺", colorRGB: 0x57C3BB, endColorRGB: 0xB173DF,
                                pattern: Self.demoSlide, generation: 3)
        let night = TouchMeaning(label: "Goodnight", emoji: "🌙", colorRGB: 0xB173DF, endColorRGB: 0x57C3BB,
                                 pattern: [600, 300, 600], generation: 2)
        let hug = TouchMeaning(label: "Hug", emoji: "🤗", colorRGB: 0xECA94B, endColorRGB: 0xEC5A89,
                               pattern: [900], generation: 2)
        store.cloudMeanings[alex.id] = [love, miss, night, hug]
        store.cloudMeanings[jo.id] = [love, night]

        let partnerID = "\(alex.id)-B"
        let now = Date()
        var touches: [TouchMessage] = [
            TouchMessage(bondID: alex.id, senderID: partnerID, pattern: Self.demoSlide, generation: 3, colorRGB: 0x57C3BB,
                         endColorRGB: 0xB173DF, sentAt: now.addingTimeInterval(-7200)),
            TouchMessage(bondID: alex.id, senderID: ChatMessage.legacySelf, pattern: [140, 120, 140, 120, 520],
                         colorRGB: 0x57C3BB, endColorRGB: 0x57C3BB, sentAt: now.addingTimeInterval(-5400)),
            TouchMessage(bondID: alex.id, senderID: partnerID, pattern: [140, 120, 140, 120, 520], colorRGB: 0xEC5A89,
                         endColorRGB: 0xB173DF, sentAt: now.addingTimeInterval(-3000), meaningLabel: "Love you", meaningEmoji: "💗"),
            TouchMessage(bondID: alex.id, senderID: ChatMessage.legacySelf, pattern: EKG.onOff(bpm: 72), generation: 2,
                         colorRGB: 0xFF2E74, endColorRGB: 0xFF2E74, sentAt: now.addingTimeInterval(-1500), heartbeatBPM: 72),
            TouchMessage(bondID: alex.id, senderID: partnerID, pattern: Self.demoSlide.reversed(), generation: 3,
                         colorRGB: 0x9FD257, endColorRGB: 0x57C3BB, sentAt: now.addingTimeInterval(-120)),
        ]
        touches[1].delivery = .seen
        touches[3].delivery = .sent
        recordTouches(touches)

        together.edit(alex.id) { s in
            s.togetherSince = Calendar.current.date(byAdding: .day, value: -412, to: now)
            s.togetherSinceEdited = now
            s.dates = [
                SpecialDate(title: "Our anniversary", date: Calendar.current.date(byAdding: .day, value: -412, to: now)!, kind: .anniversary),
                SpecialDate(title: "Alex's birthday", date: Calendar.current.date(byAdding: .day, value: 40, to: now)!, kind: .birthday),
                SpecialDate(title: "Sam's birthday", date: Calendar.current.date(byAdding: .day, value: 150, to: now)!, kind: .birthday),
            ]
            s.likes = [
                Preference(owner: "A", label: "Favourite flowers", value: "Peonies"),
                Preference(owner: "A", label: "Coffee order", value: "Oat flat white"),
                Preference(owner: "B", label: "Favourite food", value: "Ramen"),
                Preference(owner: "B", label: "Love language", value: "Touch 💞"),
            ]
            s.todos = [TodoItem(text: "Book the train to Paris", by: "A"),
                       TodoItem(text: "Pick a film for Friday", by: "B"),
                       TodoItem(text: "Send postcards", done: true, by: "A")]
            s.notes = [SharedNote(title: "Trip ideas", body: "Montmartre at sunrise, picnic by the canal, that tiny bakery.")]
            s.chess = ChessGame(moves: ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"])
        }
        together.editBoard(alex.id) { b in
            b.strokes = [Whiteboard.Stroke(rgb: 0xEC5A89, width: 6, points: Self.demoHeart, by: "A"),
                         Whiteboard.Stroke(rgb: 0x57C3BB, width: 4, points: [0.15, 0.85, 0.3, 0.8, 0.45, 0.86, 0.6, 0.8, 0.75, 0.86], by: "B")]
        }

        var w = WeatherInfo(place: "Paris", temp: 17, symbol: "cloud.sun.fill", summary: "Partly Cloudy", high: 19, low: 11)
        w.timeZone = "Europe/Paris"
        w.hours = (0..<8).map { i in .init(at: now.addingTimeInterval(Double(i) * 3600), temp: 17 + Double(i % 3) - 1,
                                           symbol: ["cloud.sun.fill", "sun.max.fill", "cloud.fill", "cloud.rain.fill"][i % 4]) }
        w.days = (0..<4).map { i in .init(date: now.addingTimeInterval(Double(i) * 86_400), high: 19 + Double(i), low: 11 + Double(i % 2),
                                          symbol: ["cloud.sun.fill", "sun.max.fill", "cloud.rain.fill", "cloud.fill"][i]) }
        partnerWeather[alex.id] = w
        var mine = w
        mine.place = "London"; mine.temp = 12; mine.summary = "Cloudy"; mine.symbol = "cloud.fill"
        myWeather = mine
        statusLine = ""
    }

    /// A slide up the bar, a hold, and back down.
    static var demoSlide: [Int] {
        var p: [Int] = []
        for i in 0..<14 { p.append(Int((Double(i) * 8 / 13).rounded())) }
        for _ in 0..<5 { p.append(8) }
        for i in 0..<16 { p.append(8 - Int((Double(i) * 8 / 15).rounded())) }
        return p.map { TouchPattern.sample([$0]) }
    }

    static var demoHeart: [Double] {
        stride(from: 0.0, through: 2 * .pi, by: 0.12).flatMap { t -> [Double] in
            let x = 16 * pow(sin(t), 3), y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            return [0.5 + x / 40, 0.42 - y / 40]
        }
    }
}
