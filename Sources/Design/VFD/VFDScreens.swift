import CoreLocation
import SwiftUI

/// The Amber VFD screens, drawn into a `VFDBuffer` from the app's state each frame. Each
/// registers its tap rectangles as it draws. Columns are placed by fractions of the width so
/// the layouts work on 3x screens (~241 cells across) and 2x ones (~207).
@MainActor
struct VFDScreens {
    let model: AppModel
    let store: LocalStore
    let ui: VFDUI
    let m: VFDMetrics
    let b: VFDBuffer
    let now: Date

    // MARK: Layout

    var cols: Int { m.cols }
    var M: Int { max(4, cols / 40) }                 // side margin
    var W: Int { cols - 2 * M }                      // content width
    func col(_ frac: Double) -> Int { M + Int((Double(W) * frac).rounded()) }

    var headerTop: Int { m.top }
    var contentTop: Int { m.top + 34 }
    var tabTop: Int { m.bottom - 27 }

    // MARK: Frame

    func draw() {
        let title: String, back: Bool
        var right: (String, UInt8)?
        switch ui.page {
        case .stand?: title = "WHERE WE STAND"; back = true
        case .themes?: title = "THEME"; back = true
        case nil:
            back = false
            switch ui.tab {
            case .home:
                title = "CONSTELLATION"
                if model.braceletState == .connected {
                    right = ("BAND ● " + (model.bracelet.batteryPercent.map { "\($0)%" } ?? "ON"), V.base)
                } else { right = ("BAND ○ OFF", V.dim) }
            case .us: title = "US"; right = partner.map { ("WITH " + $0.displayName.uppercased(), V.dim) }
            case .touches: title = "TOUCH LANGUAGE"
            case .map: title = "MAP"
            case .chat:
                title = partner?.displayName.uppercased() ?? "CHAT"
                if let p = partner { right = p.online ? ("● ONLINE", V.base) : ("○ " + seen(p), V.dim) }
            case .settings: title = "SETTINGS"
            }
        }

        // The scrolling content, between the header and the tab bar.
        let viewport = max(1, tabTop - contentTop - 1)
        ui.viewport = viewport
        b.clip(0, contentTop, cols, viewport)
        let origin = contentTop + 3 - ui.scroll
        let end: Int
        switch ui.page {
        case .stand?: end = stand(origin)
        case .themes?: end = themes(origin)
        case nil:
            switch ui.tab {
            case .home: end = home(origin)
            case .us: end = us(origin)
            case .touches: end = touches(origin)
            case .map: end = map(origin)
            case .chat: end = chat(origin, viewport: viewport)
            case .settings: end = settings(origin)
            }
        }
        ui.contentHeight = end - origin + 6
        b.unclip()

        if let flash = ui.flash {
            b.fill(0, contentTop, cols, 16, V.off)
            b.inverted(M, contentTop + 1, W, flash.text, .small, flash.alarm ? V.alarm : V.base)
        }
        header(title, back: back, right: right)
        tabBar()
    }

    private func header(_ title: String, back: Bool, right: (String, UInt8)?) {
        let t = headerTop
        b.fill(0, t, cols, 33, V.off)
        if back {
            b.text(M, t + 3, "< BACK", .small, V.base)
            b.hit(0, t, max(60, col(0.3)), 30) { ui.pop() }
            b.textFit(M, t + 15, title, W, .mid, V.text)
        } else {
            b.textFit(M, t + 9, title, W, .mid, V.text)
        }
        if let right {
            let titleEnd = M + VFDBuffer.width(title, .mid), rw = VFDBuffer.width(right.0)
            if back || titleEnd + 6 <= cols - M - rw {
                b.textRight(cols - M, t + (back ? 3 : 12), right.0, .small, right.1)
            } else {
                b.textRight(cols - M, t, right.0, .small, right.1)   // no room beside the title: above it
            }
        }
        b.hline(0, t + 32, cols, V.dim)
    }

    private var tabs: [VFDTab] { VFDTab.allCases.filter { $0 != .us || Feature.us.isOn } }

    private func tabBar() {
        let y = tabTop
        b.fill(0, y, cols, m.bottom - y, V.off)
        b.hline(0, y, cols, V.dim)
        let list = tabs, n = list.count
        for (i, tab) in list.enumerated() {
            let c0 = i * cols / n, c1 = (i + 1) * cols / n, w = c1 - c0
            let sel = tab == ui.tab
            if sel { b.fill(c0 + 1, y + 2, w - 2, 25, V.base) }
            let icon = tab.icon
            b.bitmap(c0 + (w - icon[0].count) / 2, y + 4, icon, sel ? V.off : V.dim)
            b.textCenter(c0, w, y + 17, tab.label, .small, sel ? V.off : V.text)
            b.hit(c0, y, w, m.bottom - y) { ui.select(tab) }
        }
    }

    // MARK: Shared pieces

    private var partner: Partner? { model.selectedPartner ?? livePartners.first }
    private var livePartners: [Partner] { model.partners.filter { !$0.bond.pending } }

    /// The partner chips (the chosen one lit), and + for People.
    private func chips(_ y: Int) -> Int {
        var c = M
        for p in livePartners {
            let name = VFDBuffer.fit(p.displayName.uppercased(), 60)
            let w = VFDBuffer.width(name) + 6
            if c + w > M + W - 14 { break }
            b.option(c, y, name, selected: p.id == partner?.id)
            let id = p.id
            b.hit(c, y - 2, w, 15) { model.selectedPartnerID = id }
            c += w + 3
        }
        let w = b.option(c, y, "+", selected: false)
        b.hit(c, y - 2, w + 4, 15) { ui.sheet = .people }
        return y + 16
    }

    private func section(_ y: Int, _ label: String, right: String? = nil) -> Int {
        b.text(M, y, label, .small, V.dim)
        if let right { b.textRight(M + W, y, right, .small, V.dim) }
        return y + 11
    }

    /// A full-width boxed button.
    @discardableResult
    private func button(_ y: Int, _ label: String, lit: Bool = false, _ action: @escaping () -> Void) -> Int {
        if lit { b.fill(M, y, W, 15, V.base); b.textCenter(M, W, y + 4, label, .small, V.off) }
        else { b.box(M, y, W, 15, V.dim); b.textCenter(M, W, y + 4, label, .small, V.base) }
        b.hit(M, y, W, 15, action)
        return y + 18
    }

    /// A row that opens something: label, an optional badge, and ">".
    @discardableResult
    private func row(_ y: Int, _ label: String, badge: String = "", badgeInk: UInt8 = V.base, lit: Bool = false,
                     _ action: @escaping () -> Void) -> Int {
        b.box(M, y, W, 15, lit ? V.base : V.dim)
        let badgeW = badge.isEmpty ? 0 : VFDBuffer.width(badge) + 6
        b.textFit(M + 4, y + 4, label.uppercased(), W - 20 - badgeW, .small, V.text)
        if !badge.isEmpty { b.textRight(M + W - 12, y + 4, badge, .small, badgeInk) }
        b.textRight(M + W - 3, y + 4, ">", .small, V.dim)
        b.hit(M, y, W, 15, action)
        return y + 17
    }

    private func ago(_ date: Date?) -> String {
        guard let date else { return "--" }
        let s = max(0, now.timeIntervalSince(date))
        if s < 60 { return "NOW" }
        if s < 3600 { return "\(Int(s / 60))M" }
        if s < 86_400 { return "\(Int(s / 3600))H" }
        return "\(Int(s / 86_400))D"
    }

    private func seen(_ p: Partner) -> String { p.lastSeen.map { "SEEN " + ago($0) } ?? "OFFLINE" }

    private static let usesMiles: Bool = {
        if #available(iOS 16, *) { return Locale.current.measurementSystem == .us || Locale.current.measurementSystem == .uk }
        return !Locale.current.usesMetricSystem
    }()

    /// How far away a partner is, when you both share your location.
    private func distance(_ p: Partner) -> String? {
        guard let me = model.location.lastLocation,
              let lat = p.latitude ?? p.presence?.lat, let lng = p.longitude ?? p.presence?.lng else { return nil }
        let meters = me.distance(from: CLLocation(latitude: lat, longitude: lng))
        let v = meters / (Self.usesMiles ? 1609.344 : 1000)
        return v < 100 ? String(format: "%.1f", v) : "\(Int(v.rounded()))"
    }

    private func mine(_ t: TouchMessage) -> Bool { model.isMine(t) }

    // MARK: Home

    private func home(_ y0: Int) -> Int {
        var y = y0
        guard let p = partner else {
            y = b.paragraph(M, y, "NO PARTNER YET. INVITE SOMEONE TO SEND TOUCHES, KISSES AND YOUR HEARTBEAT.", W, .small, V.text)
            return button(y + 6, "ADD A PARTNER", lit: true) { ui.sheet = .people }
        }
        y = chips(y)

        // The partner panel.
        let ph = 92
        b.box(M, y, W, ph, V.base)
        let ix = M + 4, iw = W - 8
        b.text(ix, y + 4, "♥", .mid, V.base)
        b.textFit(ix + 18, y + 4, p.displayName.uppercased(), iw - 18 - 60, .mid, V.text)
        if p.online { b.textRight(M + W - 4, y + 8, "ONLINE", .small, V.base) }
        else { b.textRight(M + W - 4, y + 8, seen(p), .small, V.dim) }
        var yy = y + 24
        let history = model.history.filter { $0.bondID == p.id }
        let last = history.map(\.sentAt).max()
        let readouts: [(String, String)] = [
            ("LAST TOUCH", ago(last)),
            ("AWAY " + (Self.usesMiles ? "MI" : "KM"), distance(p) ?? "--"),
            ("BAND %", p.presence?.braceletBattery.map(String.init) ?? "--"),
        ]
        for (i, r) in readouts.enumerated() {
            let cx = ix + i * iw / 3
            b.textFit(cx, yy, r.0, iw / 3 - 6, .small, V.dim)
            b.textFit(cx, yy + 11, r.1, iw / 3 - 4, .mid, r.1 == "--" ? V.dim : V.base)
        }
        yy += 32
        b.hline(ix, yy, iw, V.dim, step: 2)
        yy += 5
        let beat = history.last(where: { $0.heartbeatBPM != nil && !mine($0) })
        b.text(ix, yy, "HEARTBEAT BPM", .small, V.dim)
        b.text(ix, yy + 11, beat?.heartbeatBPM.map(String.init) ?? "--", .big, beat == nil ? V.dim : V.base)
        let shape: [Double] = [0, 0, 0, 0, 1, 0, -1, 8, -3, 0, 1, 1, 0, 0, 0, 0, 0]
        let shift = Int(now.timeIntervalSince1970) % shape.count
        let ekg = (0..<(shape.count * 3)).map { shape[($0 + shift) % shape.count] }
        let cx = ix + 60
        b.chart(cx, yy + 4, ix + iw - cx, 30, ekg, beat == nil ? V.dim : V.base, lo: -4, hi: 9)
        y += ph + 5

        // Touch, kiss, heartbeat.
        let id = p.id, name = p.displayName.uppercased()
        let gap = 3, bw = (W - gap * 2) / 3
        let actions: [(String, () -> Void)] = [
            ("TOUCH", { Task { let ok = await model.sendQuickTouch(toBondID: id); ui.say(ok ? "TOUCH SENT TO \(name) ♥" : "COULDN'T SEND. TRY AGAIN", alarm: !ok) } }),
            ("KISS", { Task { let ok = await model.sendKiss(toBondID: id); ui.say(ok ? "KISS SENT TO \(name)" : "COULDN'T SEND. TRY AGAIN", alarm: !ok) } }),
            ("HEARTBEAT", {
                model.selectedPartnerID = id
                ui.say("READING YOUR HEARTBEAT…")
                Task { let bpm = await model.sendHeartbeat(); ui.say(bpm.map { "HEARTBEAT SENT · \($0) BPM" } ?? "NO HEARTBEAT READING", alarm: bpm == nil) }
            }),
        ]
        for (i, a) in actions.enumerated() {
            let bx = M + i * (bw + gap)
            b.box(bx, y, bw, 15, i == 0 ? V.base : V.dim)
            b.textCenter(bx, bw, y + 4, a.0, .small, i == 0 ? V.base : V.text)
            b.hit(bx, y, bw, 15, a.1)
        }
        y += 20

        // The touch pad: the last touch, and a tap to draw one.
        let th = 64
        b.box(M, y, W, th, V.dim)
        for gy in stride(from: y + 8, to: y + th - 2, by: 8) { b.hline(M + 2, gy, W - 4, V.dim, step: 8) }
        b.textCenter(M, W, y + 4, "TAP TO DRAW A TOUCH", .small, V.dim)
        if let t = history.last(where: { $0.heartbeatBPM == nil }) {
            b.chart(M + 10, y + 14, W - 20, 46, trace(t), mine(t) ? V.text : V.base, lo: 0, hi: 1)
        }
        b.hit(M, y, W, th) { ui.sheet = .compose }
        y += th + 5

        // The streak.
        let log = model.contactLog(p.id)
        let streak = log.streak(now: now), best = max(log.bestStreak, streak)
        b.text(M, y, "STREAK DAYS", .small, V.dim)
        b.textRight(M + W, y, "BEST \(best)", .small, V.dim)
        b.text(M, y + 11, "\(streak)", .mid, streak > 0 ? V.base : V.dim)
        let barX = M + max(30, VFDBuffer.width("\(streak)", .mid) + 8)
        b.ledBar(barX, y + 15, M + W - barX, fill: best > 0 ? Double(streak) / Double(best) : 0,
                 markers: best > 0 ? [(1.0, V.text)] : [])
        y += 32

        // Recent, everyone.
        y = section(y, "RECENT")
        for e in recent().prefix(8) {
            b.text(M, y, VFDBuffer.fit(e.who, col(0.2) - M - 2), .small, e.ink)
            b.textFit(col(0.22), y, e.what, col(0.86) - col(0.22), .small, e.ink == V.alarm ? V.alarm : V.text)
            b.textRight(M + W, y, ago(e.at), .small, V.dim)
            y += 11
        }
        if recent().isEmpty { b.text(M, y, "NOTHING YET", .small, V.dim); y += 11 }
        return y
    }

    private struct Event { let who: String, what: String, at: Date, ink: UInt8 }

    private func recent() -> [Event] {
        let names = Dictionary(model.partners.map { ($0.id, $0.displayName.uppercased()) }, uniquingKeysWith: { a, _ in a })
        var out: [Event] = model.receivedKisses.prefix(10).map { Event(who: $0.name.uppercased(), what: "KISSED YOU", at: $0.at, ink: V.base) }
        for t in model.history.suffix(30) {
            let me = mine(t)
            let what: String
            if let bpm = t.heartbeatBPM { what = "HEARTBEAT \(bpm) BPM" }
            else if let label = t.meaningLabel { what = (me ? "SENT " : "") + label.uppercased() }
            else { what = me ? "SENT A TOUCH" : "TOUCHED YOU ♥" }
            out.append(Event(who: me ? "YOU" : names[t.bondID] ?? "PARTNER", what: what, at: t.sentAt, ink: me ? V.text : V.base))
        }
        return out.sorted { $0.at > $1.at }
    }

    /// A touch as a line: the finger position on the bar (generation 3), or presses (2).
    private func trace(_ t: TouchMessage) -> [Double] {
        if t.generation == 3 {
            let n = max(1, TouchPattern.positions - 1)
            var last = 0.5
            let v = t.pattern.map { s -> Double in
                if let f = TouchPattern.fingers(in: s).first { last = Double(f) / Double(n) }
                return last
            }
            return v.count > 1 ? v : [0.5, 0.5]
        }
        var out: [Double] = [0]
        for (i, ms) in t.pattern.prefix(40).enumerated() {
            let steps = max(1, min(12, ms / 60))
            out += Array(repeating: i % 2 == 0 ? 0.85 : 0.1, count: steps)
        }
        out.append(0)
        return out.count > 1 ? out : [0.1, 0.1]
    }

    // MARK: Us

    private func us(_ y0: Int) -> Int {
        var y = y0
        if let p = partner, let due = model.standNextCheckIn(p.id) {
            let f = DateFormatter(); f.dateFormat = "EEE d MMM"
            b.inverted(M, y, W, "CHECK-IN DUE " + f.string(from: due).uppercased() + " ♥", .small, due < now ? V.alarm : V.base)
            b.hit(M, y, W, 12) { ui.push(.stand) }
            y += 18
        }
        var parts: [(String, String, Bool)] = [
            ("stand", "Where we stand", Feature.stand.isOn),
            ("language", "Touch language", true),
            ("todos", "To-do", Feature.todos.isOn),
            ("notes", "Notes", Feature.notes.isOn),
            ("dates", "Special dates", Feature.dates.isOn),
            ("whiteboard", "Whiteboard", Feature.whiteboard.isOn),
            ("games", "Games", Feature.games.isOn),
            ("stress", "Stress & mood", Feature.stress.isOn),
            ("question", "Question of the day", Feature.question.isOn),
            ("jar", "Appreciation jar", Feature.appreciation.isOn),
            ("love", "Love languages", Feature.loveLanguages.isOn),
            ("roulette", "Date roulette", Feature.dateRoulette.isOn),
            ("memories", "Memory lane", Feature.memories.isOn),
            ("agreements", "Agreements", Feature.agreements.isOn),
            ("repair", "Repair", Feature.repair.isOn),
            ("radar", "R.A.D.A.R.", Feature.radar.isOn),
            ("polycal", "Poly calendar", Feature.polyCalendar.isOn),
            ("metamours", "Metamours", Feature.metamours.isOn),
            ("likes", "Profiles side by side", Feature.likes.isOn),
        ]
        parts = parts.filter { $0.2 }
        for (id, title, _) in parts {
            var badge = "", ink = V.base
            if id == "stand", let p = partner {
                let a = model.standLatest(p.id, by: model.myRole(p.id)), them = model.standLatest(p.id, by: model.standThem(p.id))
                let shape = StandAlignment.of(a, them)
                badge = shape == .goodPlace ? "ALIGNED" : shape == .waiting ? "" : shape == .checkIn ? "CHECK IN" : ""
                if model.standPromises(model.standScope(p.id)).contains(where: { $0.slipped }) { badge = "1 MISSED"; ink = V.alarm }
            }
            y = row(y, title, badge: badge, badgeInk: ink, lit: id == "stand") {
                if id == "stand" { ui.push(.stand) } else { ui.sheet = .part(id) }
            }
        }
        return y
    }

    // MARK: Where we stand

    private func stand(_ y0: Int) -> Int {
        var y = y0
        guard let p = partner else { return b.paragraph(M, y, "ADD A PARTNER FIRST.", W) }
        let id = p.id, name = p.displayName.uppercased()
        let me = model.myRole(id), them = model.standThem(id)
        let scope = model.standScope(id)
        let a = model.standLatest(id, by: me), other = model.standLatest(id, by: them)
        let shape = StandAlignment.of(a, other)
        y = chips(y)

        b.inverted(M, y, W, shape.title.uppercased(), .small, shape == .checkIn ? V.alarm : V.base)
        y += 15
        let detail = StandAlignment.detail(a, other, name: p.displayName)
        if !detail.isEmpty { y = b.paragraph(M, y, detail.uppercased(), W, .small, V.text) + 4 }

        // Closeness: your own number; theirs only if they share it.
        b.text(M, y, "CLOSENESS", .small, V.dim)
        b.textRight(M + W, y, other?.closeness != nil ? "YOU ● \(name) ○" : "YOU ●", .small, V.dim)
        y += 12
        var markers: [(Double, UInt8)] = []
        if let theirs = other?.closeness { markers.append((Double(theirs) / 10, V.text)) }
        if let a { markers.append((Double(StandPrivate.closeness(a)) / 10, V.base)) }
        b.ledBar(M, y, W, markers: markers)
        y += 8
        b.text(M, y, "APART", .small, V.dim)
        if let a { b.textCenter(M, W, y, "\(StandPrivate.closeness(a))/10", .small, V.base) }
        b.textRight(M + W, y, "CLOSE", .small, V.dim)
        y += 14

        // Your style and how you feel about it.
        if let a {
            if !a.styles.isEmpty {
                b.text(M, y, "STYLE", .small, V.dim); y += 11
                var c = M
                let shared = Set(StandStyles.overlap(a.styles, other?.styles ?? []).map { $0.lowercased() })
                for s in a.styles {
                    let label = s.uppercased() + (shared.contains(s.lowercased()) ? " ✓" : "")
                    let w = VFDBuffer.width(label) + 6
                    if c + w > M + W { c = M; y += 14 }
                    b.option(c, y, label, selected: true)
                    c += w + 3
                }
                y += 16
            }
            b.text(M, y, "HOW YOU FEEL", .small, V.dim); y += 11
            var c = M
            for h in StandHappiness.allCases {
                let label = h.title.uppercased(), w = VFDBuffer.width(label) + 6
                if c + w > M + W { c = M; y += 14 }
                b.option(c, y, label, selected: a.happy == h)
                c += w + 3
            }
            y += 18
        }

        // Wishes.
        let wishes = model.standWishes(scope).filter { !($0.isHidden && $0.by != me) }
        let marks = model.standMarks(scope).live(.answer)
        y = section(y, "WISHES", right: wishes.isEmpty ? nil : "\(wishes.count) OPEN")
        for w in wishes.prefix(8) {
            let answer = marks.last(where: { $0.item == w.id && $0.by != w.by }).flatMap { StandAnswer(rawValue: $0.value) }
            let state = answer?.title.uppercased() ?? (w.by == me ? "WAITING" : "YOUR ANSWER?")
            b.textFit(M, y, w.title.uppercased(), col(0.55) - M, .small, V.text)
            b.textRight(M + W, y, state, .small, answer == .yes ? V.base : answer == nil && w.by != me ? V.base : V.dim)
            y += 11
        }
        if wishes.isEmpty { b.text(M, y, "NONE YET", .small, V.dim); y += 11 }
        y += 4

        // Promises.
        let promises = model.standPromises(scope).filter { $0.status == .open || $0.status == .kept }
        let missed = promises.filter(\.slipped).count
        y = section(y, "PROMISES", right: missed > 0 ? "\(missed) MISSED" : nil)
        for pr in promises.prefix(8) {
            let state: String, ink: UInt8
            if pr.slipped { state = "MISSED · TALK?"; ink = V.alarm }
            else if pr.status == .kept { state = "✓ KEPT"; ink = V.base }
            else if let due = pr.due {
                let f = DateFormatter(); f.dateFormat = "d MMM"
                state = "DUE " + f.string(from: due).uppercased(); ink = V.dim
            } else { state = "OPEN"; ink = V.dim }
            b.textFit(M, y, pr.title.uppercased(), col(0.55) - M, .small, V.text)
            b.textRight(M + W, y, state, .small, ink)
            y += 11
        }
        if promises.isEmpty { b.text(M, y, "NONE YET", .small, V.dim); y += 11 }
        y += 6

        // Your closeness over time.
        let readings = model.standReadings(id, by: me)
        if readings.count > 1 {
            b.text(M, y, "YOUR CLOSENESS OVER TIME", .small, V.dim)
            if let a { b.textRight(M + W, y, "NOW \(StandPrivate.closeness(a))/10", .small, V.base) }
            y += 11
            b.chart(M, y, W, 40, readings.suffix(30).map { Double(StandPrivate.closeness($0)) }, V.base, lo: 0, hi: 10)
            y += 46
        }
        if let next = model.standNextCheckIn(id) {
            let f = DateFormatter(); f.dateFormat = "EEE d MMM"
            b.text(M, y, "NEXT CHECK-IN", .small, V.dim)
            b.textRight(M + W, y, f.string(from: next).uppercased(), .small, next < now ? V.alarm : V.base)
            y += 13
            if model.standMoodLow {
                b.inverted(M, y, W, "MOOD IS LOW · MOVE CHECK-IN?", .small, V.alarm)
                b.hit(M, y, W, 12) { model.standMoveCheckIn(id); ui.say("CHECK-IN MOVED 3 DAYS") }
                y += 16
            }
        }
        y += 2
        return button(y, a == nil ? "SAY WHERE YOU STAND" : "UPDATE WHERE I STAND", lit: true) { ui.sheet = .part("stand") }
    }

    // MARK: Touch language

    private func touches(_ y0: Int) -> Int {
        var y = y0
        let meanings = model.currentMeanings
        y = section(y, "YOUR TOUCHES", right: "\(meanings.count)")
        for t in meanings {
            b.box(M, y, W, 15, V.dim)
            b.textFit(M + 4, y + 4, t.label.uppercased(), col(0.6) - M - 4, .small, V.text)
            let fake = TouchMessage(senderID: "", pattern: t.pattern, colorRGB: t.colorRGB)
            b.chart(col(0.62), y + 2, M + W - 4 - col(0.62), 11, trace(fake), V.base, lo: 0, hi: 1)
            b.hit(M, y, W, 15) { ui.sheet = .meanings }
            y += 17
        }
        if meanings.isEmpty { y = b.paragraph(M, y, "NO TOUCHES SAVED YET. GIVE A RHYTHM A MEANING AND IT SHOWS ON THEIR SCREEN.", W) + 4 }
        y += 4
        return button(y, "EDIT TOUCH LANGUAGE", lit: true) { ui.sheet = .meanings }
    }

    // MARK: Map

    private func map(_ y0: Int) -> Int {
        var y = y0
        b.text(M, y, "PARTNER", .small, V.dim)
        b.text(col(0.45), y, "AWAY " + (Self.usesMiles ? "MI" : "KM"), .small, V.dim)
        b.textRight(M + W, y, "UPDATED", .small, V.dim)
        y += 12
        for p in livePartners {
            let d = distance(p)
            b.textFit(M, y, p.displayName.uppercased(), col(0.43) - M, .small, V.text)
            b.text(col(0.45), y, d ?? "--", .mid, d == nil ? V.dim : V.base)
            b.textRight(M + W, y + 4, ago(p.presence?.locationAt), .small, V.dim)
            let id = p.id
            b.hit(M, y - 2, W, 18) { model.selectedPartnerID = id; ui.sheet = .map }
            y += 20
        }
        if livePartners.isEmpty { b.text(M, y, "NO PARTNERS YET", .small, V.dim); y += 12 }
        if model.location.lastLocation == nil {
            y = b.paragraph(M, y + 2, "YOUR LOCATION ISN'T AVAILABLE, SO DISTANCES CAN'T BE WORKED OUT.", W, .small, V.alarm) + 4
        }
        y += 4
        return button(y, "OPEN THE MAP", lit: true) { ui.sheet = .map }
    }

    // MARK: Chat

    private func chat(_ y0: Int, viewport: Int) -> Int {
        var y = y0
        guard store.hasPrivateSpace else {
            y = b.paragraph(M, y, "CHAT LIVES IN PRIVATE SPACE, BEHIND A PASSCODE. SET IT UP TO START.", W) + 6
            return button(y, "SET UP PRIVATE SPACE", lit: true) { ui.sheet = .privateSpace }
        }
        guard ui.chatUnlocked else {
            b.bitmap(M + (W - 7) / 2, y + 4, ["..###..", ".#...#.", ".#...#.", "#######", "###.###", "###.###", "#######"], V.base)
            b.textCenter(M, W, y + 16, "PRIVATE SPACE IS LOCKED", .small, V.text)
            y += 32
            y = button(y, "UNLOCK", lit: true) { VFDUnlock.unlock(ui) }
            return button(y, "USE PASSCODE") { ui.sheet = .privateSpace }
        }
        guard let p = partner else { return b.paragraph(M, y, "ADD A PARTNER TO CHAT.", W) }
        y = chips(y)
        let messages = (model.messagesByBond[p.id] ?? []).sorted { $0.sentAt < $1.sentAt }.suffix(60)
        let bw = Int(Double(W) * 0.76)
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        var lastDay: Date?
        for msg in messages {
            if lastDay == nil || !Calendar.current.isDate(msg.sentAt, inSameDayAs: lastDay!) {
                let df = DateFormatter(); df.dateFormat = Calendar.current.isDateInToday(msg.sentAt) ? "'TODAY'" : "EEE d MMM"
                b.textCenter(0, cols, y, "— " + df.string(from: msg.sentAt).uppercased() + " —", .small, V.dim)
                y += 14
                lastDay = msg.sentAt
            }
            let me = msg.senderID == model.myUserID || msg.senderID == ChatMessage.legacySelf
            let x = me ? M + W - bw : M
            let top = y
            var inner = y + 4
            switch msg.kind {
            case .image:
                b.bitmap(x + 4, inner, ["###########", "#.........#", "#.##......#", "#.##...#..#", "#.....###.#", "#..#.#####.", "#.#########", "###########"], V.dim)
                let timed = (msg.viewSeconds ?? 0) > 0
                let label = msg.expired == true ? "PHOTO · VIEWED" : timed ? "PHOTO · \(msg.viewSeconds ?? 0) S" : "PHOTO"
                b.text(x + 18, inner + 1, label, .small, msg.expired == true ? V.dim : V.base)
                b.text(x + 4, inner + 12, msg.expired == true ? "GONE FROM THIS PHONE" : timed ? "TAP TO VIEW ONCE" : "TAP TO VIEW", .small, V.dim)
                inner += 21
                b.hit(x, top, bw, inner - top + 2) { ui.sheet = .chat }
            case .touch:
                b.text(x + 4, inner, me ? "♥ YOU SENT A TOUCH" : "♥ A TOUCH", .small, V.base)
                inner += 10
            case .text:
                let alarm = msg.text.hasPrefix("📸")
                inner = b.paragraph(x + 4, inner, msg.text, bw - 8, .small, alarm ? V.alarm : V.text)
            }
            let h = inner - top + 2
            b.box(x, top, bw, h, me ? V.base : V.dim)
            let time = tf.string(from: msg.sentAt)
            if me { b.textRight(x + bw, top + h + 2, time, .small, V.dim) } else { b.text(x, top + h + 2, time, .small, V.dim) }
            y = top + h + 13
        }
        if messages.isEmpty { b.textCenter(0, cols, y, "SAY HELLO", .small, V.dim); y += 14 }
        // The composer (part of the content, so it scrolls with the last message).
        y += 2
        let sendW = 31, photoW = 37
        b.box(M, y, W - sendW - photoW - 6, 15, V.dim)
        b.text(M + 4, y + 4, "MESSAGE_", .small, V.dim)
        let id = p.id
        b.hit(M, y, W - sendW - photoW - 6, 15) {
            ui.ask("Message \(p.displayName)", placeholder: "Message") { text in Task { await model.sendChatText(text, toBondID: id) } }
        }
        let px = M + W - sendW - photoW - 3
        b.box(px, y, photoW, 15, V.dim); b.textCenter(px, photoW, y + 4, "PHOTO", .small, V.base)
        b.hit(px, y, photoW, 15) { ui.sheet = .chat }
        b.fill(M + W - sendW, y, sendW, 15, V.base); b.textCenter(M + W - sendW, sendW, y + 4, "SEND", .small, V.off)
        b.hit(M + W - sendW, y, sendW, 15) {
            ui.ask("Message \(p.displayName)", placeholder: "Message") { text in Task { await model.sendChatText(text, toBondID: id) } }
        }
        y += 16
        // Open at the newest message.
        if ui.scrolls[ui.pageKey] == nil {
            let height = y - y0 + 6
            ui.contentHeight = height
            ui.scrolls[ui.pageKey] = max(0, height - viewport)
        }
        return y
    }

    // MARK: Settings

    private func settings(_ y0: Int) -> Int {
        var y = y0
        // Alarms first.
        if let level = model.bracelet.batteryPercent, model.braceletState == .connected, level <= 15 {
            b.inverted(M, y, W, "YOUR BAND BATTERY LOW · \(level)%", .small, V.alarm); y += 16
        }
        for p in livePartners {
            if let level = p.presence?.braceletBattery, p.presence?.bracelet == true, level <= 15 {
                b.inverted(M, y, W, "\(p.displayName.uppercased())’S BAND BATTERY LOW · \(level)%", .small, V.alarm); y += 16
            }
        }

        y = section(y, "APPEARANCE")
        b.text(M, y + 2, "THEME", .small, V.text)
        let theme = AppStyle.vfd.title.uppercased(), tw = VFDBuffer.width(theme) + 6
        b.option(M + W - tw, y, theme, selected: true)
        b.hit(M, y - 2, W, 15) { ui.push(.themes) }
        y += 15
        b.text(M, y, "BASE COLOUR", .small, V.text); y += 11
        let picked = ThemeTints.tint(for: .vfd) ?? VFDPalette.amber
        let per = 3, gap = 3, sw = (W - gap * (per - 1)) / per
        for (i, base) in VFDPalette.bases.enumerated() {
            let bx = M + (i % per) * (sw + gap), by = y + (i / per) * 16
            let ink = b.swatch(base.rgb), name = base.name.uppercased()
            if base.rgb == picked { b.fill(bx, by, sw, 13, ink); b.textCenter(bx, sw, by + 3, name, .small, V.off) }
            else { b.box(bx, by, sw, 13, ink); b.textCenter(bx, sw, by + 3, name, .small, ink) }
            let rgb = base.rgb
            b.hit(bx, by, sw, 13) {
                var d = ThemeTints.parse(UserDefaults.standard.string(forKey: ThemeTints.key) ?? "")
                d[AppStyle.vfd.rawValue] = rgb == VFDPalette.amber ? nil : rgb
                UserDefaults.standard.set(ThemeTints.encode(d), forKey: ThemeTints.key)
            }
        }
        y += ((VFDPalette.bases.count + per - 1) / per) * 16 + 4
        b.hline(M, y, W, V.dim, step: 2); y += 5

        y = section(y, "BRACELET")
        let connected = model.braceletState == .connected
        b.text(M, y, "STATUS", .small, V.text)
        b.textRight(M + W, y, connected ? "CONNECTED" : model.braceletState == .scanning ? "LOOKING…" : "NOT CONNECTED", .small, connected ? V.base : V.dim)
        y += 11
        if let level = model.bracelet.batteryPercent, connected {
            b.text(M, y, "BATTERY %", .small, V.text); b.textRight(M + W, y, "\(level)", .small, level <= 15 ? V.alarm : V.base)
            y += 10
            b.ledBar(M, y, W, fill: Double(level) / 100, level <= 15 ? V.alarm : V.base)
            y += 10
        }
        b.text(M, y + 2, "TOUCH WINDOW S", .small, V.text)
        let st = b.stepper(M + W, y, "\(Int(store.touchWindowSeconds))")
        b.hit(st.minus, y, st.w, 11) { store.touchWindowSeconds = max(5, store.touchWindowSeconds - 1) }
        b.hit(st.plus, y, st.w, 11) { store.touchWindowSeconds = min(10, store.touchWindowSeconds + 1) }
        y += 15
        b.hline(M, y, W, V.dim, step: 2); y += 5

        y = section(y, "BACKGROUND")
        let toggles: [(String, Bool, (Bool) -> Void)] = [
            ("STAY CONNECTED", store.keepAliveInBackground, { on in store.keepAliveInBackground = on; model.updateKeepAlive() }),
            ("WATCH STANDS IN", store.watchStandsIn, { on in store.watchStandsIn = on }),
        ]
        for (label, on, set) in toggles {
            b.textFit(M, y + 2, label, W - 50, .small, V.text)
            let t = b.toggle(M + W, y, on: on)
            b.hit(t.x, y - 1, t.w, 13) { set(!on) }
            y += 15
        }
        if let p = partner {
            let days = NudgeInterval.days(for: p.id)
            b.textFit(M, y + 2, "NUDGE ABOUT \(p.displayName.uppercased())", W - 80, .small, V.text)
            let st = b.stepper(M + W, y, NudgeInterval.title(days).uppercased())
            let choices = NudgeInterval.choices, i = choices.firstIndex(of: days) ?? 0, id = p.id
            b.hit(st.minus, y, st.w, 11) { NudgeInterval.set(choices[max(0, i - 1)], for: id); model.scheduleNudgesSoon() }
            b.hit(st.plus, y, st.w, 11) { NudgeInterval.set(choices[min(choices.count - 1, i + 1)], for: id); model.scheduleNudgesSoon() }
            y += 17
        }
        b.hline(M, y, W, V.dim, step: 2); y += 5
        y = row(y, "People") { ui.sheet = .people }
        y = row(y, "What's new") { ui.sheet = .whatsNew }
        y = row(y, "All settings") { ui.sheet = .settings }
        y += 4
        b.textCenter(0, cols, y, "CONSTELLATION", .small, V.dim)
        return y + 10
    }

    // MARK: Themes

    private func themes(_ y0: Int) -> Int {
        var y = y0
        let current = Theme.style
        for style in AppStyle.allCases {
            let sel = style == current
            if sel { b.fill(M, y, W, 15, V.base); b.text(M + 4, y + 4, style.title.uppercased(), .small, V.off) }
            else { b.box(M, y, W, 15, V.dim); b.text(M + 4, y + 4, style.title.uppercased(), .small, V.text) }
            b.hit(M, y, W, 15) {
                ThemePickerCard.keepPlace()
                UserDefaults.standard.set(style.rawValue, forKey: "appStyle")
            }
            y += 17
        }
        return y
    }
}
