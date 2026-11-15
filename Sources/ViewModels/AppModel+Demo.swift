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
                if let s = v as? UIScrollView, s.contentSize.height > 0,
                   s.contentSize.width <= s.bounds.width + 1,
                   s.contentSize.height + s.adjustedContentInset.top + s.adjustedContentInset.bottom > s.bounds.height {
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
        loadStandDemo(alexID: alex.id, joID: jo.id, now: now)
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

    /// Where we stand for the demo: both meters with some history, a few wishes (one answered
    /// "Not yet", one hidden), a promise coming up and a kept one, and an "All of us" group
    /// with Alex and Jo.
    private func loadStandDemo(alexID: String, joID: String, now: Date) {
        let cal = Calendar.current
        func ago(_ days: Int) -> Date { cal.date(byAdding: .day, value: -days, to: now) ?? now }
        func ahead(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: now) ?? now }

        var readings: [StandReading] = []
        for (days, c) in [(120, 6), (90, 7), (60, 7), (31, 8), (3, 8)] {
            var r = StandReading(by: "A", closeness: c, band: StandReading.band(c), note: days == 3 ? "Feeling really settled with you" : nil,
                                 styles: ["Anchor", "Nesting", "Partners"], happiness: StandHappiness.content.rawValue,
                                 working: ["Sunday mornings", "How we talk things through"], moreOf: ["Weekends away"],
                                 pace: StandPace.steady.rawValue)
            r.created = ago(days); r.edited = r.created
            readings.append(r)
        }
        for (days, c, happy) in [(118, 6, StandHappiness.more), (62, 7, StandHappiness.more), (30, 8, StandHappiness.content), (2, 9, StandHappiness.content)] {
            var r = StandReading(by: "B", band: StandReading.band(c), styles: ["Anchor", "Partners", "Long-distance"],
                                 happiness: happy.rawValue, working: ["Our calls before bed", "Feeling like a team"],
                                 moreOf: ["Trips together"], lessOf: ["Rushed goodbyes"], pace: StandPace.ready.rawValue)
            r.created = ago(days); r.edited = r.created
            readings.append(r)
        }

        var weekend = StandWish(by: "B", title: "A weekend away", library: "weekend", matters: true)
        weekend.created = ago(20)
        var family = StandWish(by: "A", title: "Meet family", library: "family")
        family.created = ago(14)
        var travel = StandWish(by: "B", title: "Travel together", library: "travel")
        travel.created = ago(1)
        let moveIn = StandLibrary.item("movein").map { StandWish(by: "A", hidden: StandLibrary.hiddenHash($0, bondCode: alexID)) }

        var asheville = StandPromise(by: "B", title: "Asheville weekend", due: ahead(12), note: "The cabin with the porch", wish: weekend.id)
        asheville.created = ago(18)
        weekend.promise = asheville.id
        var risotto = StandPromise(by: "A", title: "Cook for Alex's birthday", state: StandPromiseState.kept.rawValue, stateAt: ago(20))
        risotto.created = ago(40)

        together.edit(alexID) { s in
            s.standReadings = readings
            s.standWishes = [weekend, family, travel] + (moveIn.map { [$0] } ?? [])
            s.standPromises = [risotto, asheville]
            s.standMarks = [
                StandMark(.rhythm, by: "A", value: "30", shared: true),
                StandMark(.answer, item: weekend.id, by: "A", value: StandAnswer.yes.rawValue),
                StandMark(.answer, item: family.id, by: "B", value: StandAnswer.notYet.rawValue, until: ahead(60)),
                StandMark(.seen, item: family.id, by: "B"),
                StandMark(.seen, item: weekend.id, by: "A"),
                StandMark(.thanks, item: risotto.id, by: "B", value: "Best risotto of my life 💛"),
            ]
        }

        // A triad: Alex and Jo are bonded with each other too.
        let alexPerson = "D0000000-0000-0000-0000-00000000A1E7", joPerson = "D0000000-0000-0000-0000-0000000000B0"
        var known = StandPeople.known()
        known[alexID] = .init(personID: alexPerson, links: [StandPeople.linkHash(joPerson), StandPeople.linkHash(StandPeople.myID)])
        known[joID] = .init(personID: joPerson, links: [StandPeople.linkHash(alexPerson), StandPeople.linkHash(StandPeople.myID)])
        StandPeople.saveKnown(known)
        let key = StandPeople.groupKey([alexPerson, joPerson, StandPeople.myID])
        var night = StandWish(by: joPerson, title: "A games night, all of us", matters: true, groupKey: key)
        night.created = ago(4)
        let picnic = StandPromise(by: alexPerson, title: "Picnic at the lake", due: ahead(5), groupKey: key)
        for id in [alexID, joID] {
            together.edit(id) { s in
                s.standGroupWishes = [night]
                s.standGroupPromises = [picnic]
                s.standGroupMarks = [StandMark(.answer, item: night.id, by: alexPerson, value: StandAnswer.yes.rawValue, groupKey: key)]
            }
        }
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
