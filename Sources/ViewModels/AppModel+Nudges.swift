import Foundation
import UserNotifications

/// What this phone has seen of each partnership: when you last reached out, when they last
/// did, and which days you were in touch (any touch, heartbeat, kiss or message, either way).
/// Kept on this phone only; it drives the nudges, streaks and the balance.
struct ContactLog: Codable {
    var lastSent: Date?
    var lastReceived: Date?
    /// "yyyy-MM-dd" → [sent, received] that day (the last 60 days).
    var days: [String: [Int]] = [:]
    var bestStreak = 0

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Days in a row you were in touch, up to today (or up to yesterday, if today hasn't
    /// counted yet: a streak isn't broken until the day is over).
    func streak(now: Date = Date()) -> Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: now)
        if days[Self.dayKey(day)] == nil { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var n = 0
        while days[Self.dayKey(day)] != nil {
            n += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return n
    }

    var inTouchToday: Bool { days[Self.dayKey(Date())] != nil }

    /// Sent and received in the last `days` days, today included.
    func counts(lastDays: Int, now: Date = Date()) -> (sent: Int, received: Int) {
        let cal = Calendar.current
        var sent = 0, received = 0
        for i in 0..<lastDays {
            guard let d = cal.date(byAdding: .day, value: -i, to: now), let v = days[Self.dayKey(d)] else { continue }
            sent += v[0]; received += v[1]
        }
        return (sent, received)
    }
}

enum ContactLogStore {
    private static let key = "contactLog"
    static func load() -> [String: ContactLog] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: ContactLog].self, from: $0) } ?? [:]
    }
    static func save(_ logs: [String: ContactLog]) {
        if let data = try? JSONEncoder().encode(logs) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Per-partner "remind me after" for the It's-been-a-while nudge, in days (0 = off).
enum NudgeInterval {
    static let choices = [0, 1, 2, 3, 7]
    static let `default` = 2
    static func days(for bondID: String) -> Int {
        UserDefaults.standard.object(forKey: "nudge.interval.\(bondID)") as? Int ?? Self.default
    }
    static func set(_ days: Int, for bondID: String) {
        UserDefaults.standard.set(days, forKey: "nudge.interval.\(bondID)")
    }
    static func title(_ days: Int) -> String {
        switch days {
        case 0: return "Off"
        case 7: return "A week"
        default: return "\(days) day\(days == 1 ? "" : "s")"
        }
    }
}

extension AppModel {
    // MARK: Logging contact

    /// Notes contact with a partner (`mine`: you reached out). Updates streaks and the nudges.
    func noteContact(bondID: String, mine: Bool, at date: Date = Date()) {
        guard !Self.isDemo, partners.contains(where: { $0.id == bondID }) else { return }
        var log = contactLogs[bondID] ?? ContactLog()
        if mine { log.lastSent = max(log.lastSent ?? .distantPast, date) }
        else { log.lastReceived = max(log.lastReceived ?? .distantPast, date) }
        let key = ContactLog.dayKey(date)
        var v = log.days[key] ?? [0, 0]
        v[mine ? 0 : 1] += 1
        log.days[key] = v
        // Keep 60 days.
        if let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) {
            let oldest = ContactLog.dayKey(cutoff)
            log.days = log.days.filter { $0.key >= oldest }
        }
        log.bestStreak = max(log.bestStreak, log.streak())
        contactLogs[bondID] = log
        ContactLogStore.save(contactLogs)
        scheduleNudgesSoon()
    }

    func contactLog(_ bondID: String) -> ContactLog { contactLogs[bondID] ?? ContactLog() }

    // MARK: Scheduling

    private static var nudgeTask: Task<Void, Never>?

    /// Rebuilds the nudges a moment after things settle (many events can arrive at once).
    func scheduleNudgesSoon() {
        Self.nudgeTask?.cancel()
        Self.nudgeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self.scheduleNudges()
        }
    }

    /// Every nudge is a local notification scheduled ahead on this phone, rebuilt whenever
    /// something changes, so it fires even with the app closed and never fires stale.
    /// Nothing is ever sent to a partner. All between 10:00 and 21:00.
    func scheduleNudges() async {
        guard !Self.isDemo else { return }
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("nudge-") }
        center.removePendingNotificationRequests(withIdentifiers: old)

        let now = Date()
        let cal = Calendar.current
        var requests: [UNNotificationRequest] = []
        func add(_ id: String, _ bondID: String?, at fire: Date, title: String, body: String) {
            guard fire > now.addingTimeInterval(60) else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = TouchNotification.partnerCategory
            content.threadIdentifier = "nudges"
            if let bondID { content.userInfo = [TouchNotification.Key.bond: bondID] }
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            requests.append(UNNotificationRequest(identifier: id, content: content,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false)))
        }

        for p in partners where !p.bond.pending {
            let log = contactLog(p.id)
            let name = p.displayName

            // 1. It's been a while: X days after you last reached out (every X days while quiet).
            let interval = NudgeInterval.days(for: p.id)
            if NotificationKind.nudgeWhile.isOn, interval > 0 {
                let step = TimeInterval(interval) * 86_400
                var fire = (log.lastSent ?? now).addingTimeInterval(step)
                while fire < now { fire += step }
                let days = Int((fire.timeIntervalSince(log.lastSent ?? now) / 86_400).rounded())
                let streak = log.streak()
                add("nudge-while-\(p.id)", p.id, at: Self.inWindow(fire),
                    title: "Thinking of \(name)? 💞",
                    body: streak >= 2 ? "You two are on a \(streak)-day streak. Send a touch or a kiss?"
                                      : "It's been \(days) day\(days == 1 ? "" : "s") since you reached out. Send a touch or a kiss?")
            }

            // 2. A touch you haven't answered: 3 hours later, the same day.
            if NotificationKind.nudgeReply.isOn, let got = log.lastReceived, got > (log.lastSent ?? .distantPast),
               now.timeIntervalSince(got) < 24 * 3600 {
                let fire = got.addingTimeInterval(3 * 3600)
                if cal.isDate(fire, inSameDayAs: got), cal.component(.hour, from: fire) < 21 {
                    add("nudge-reply-\(p.id)", p.id, at: Self.inWindow(fire),
                        title: "\(name) reached out earlier 🤍", body: "Send one back?")
                }
            }

            // 3. Moments: the evening before you meet.
            if NotificationKind.nudgeMoments.isOn, let meet = store.nextMeeting(for: p.id),
               let eve = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: meet)),
               let fire = cal.date(bySettingHour: 19, minute: 0, second: 0, of: eve) {
                add("nudge-meet-\(p.id)", p.id, at: fire,
                    title: "Tomorrow you see \(name) 💞", body: "Send something sweet before then?")
            }

            // 5. Gone quiet: a week since they last reached out. Once per quiet spell; they're never told.
            if NotificationKind.nudgeQuiet.isOn, let got = log.lastReceived {
                add("nudge-quiet-\(p.id)", p.id, at: Self.inWindow(got.addingTimeInterval(7 * 86_400), hour: 18),
                    title: "\(name) has been quiet for a week", body: "Maybe check in? 💛")
            }

            // 6. Streak: 20:00 if you're on a streak of 2+ days and haven't been in touch today.
            let streak = log.streak()
            if NotificationKind.nudgeStreak.isOn, streak >= 2, !log.inTouchToday,
               let fire = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now) {
                add("nudge-streak-\(p.id)", p.id, at: fire,
                    title: "🔥 \(streak) days with \(name)", body: "One touch today keeps it going.")
            }
        }

        // 7. Balance: Sunday at 18:30, when there's more than one partner. Only you see it.
        if NotificationKind.nudgeBalance.isOn, partners.count > 1, let summary = balanceSummary() {
            var c = DateComponents(); c.weekday = 1; c.hour = 18; c.minute = 30
            if let fire = cal.nextDate(after: now, matching: c, matchingPolicy: .nextTime) {
                add("nudge-balance", nil, at: fire, title: "Your week with your people 💞", body: summary)
            }
        }

        for r in requests { try? await center.add(r) }
    }

    /// The same moment, moved into 10:00–21:00 (to `hour` the next morning if too late).
    static func inWindow(_ date: Date, hour: Int? = nil) -> Date {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        if let hour { return cal.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date }
        if h < 10 { return cal.date(bySettingHour: 10, minute: 0, second: 0, of: date) ?? date }
        if h >= 21, let next = cal.date(byAdding: .day, value: 1, to: date) {
            return cal.date(bySettingHour: 10, minute: 0, second: 0, of: next) ?? date
        }
        return date
    }

    // MARK: Balance

    /// One row per partner for the last 7 days, most contact first.
    func balance(days: Int = 7) -> [(partner: Partner, sent: Int, received: Int)] {
        partners.filter { !$0.bond.pending }
            .map { p in let c = contactLog(p.id).counts(lastDays: days); return (p, c.sent, c.received) }
            .sorted { ($0.sent + $0.received) > ($1.sent + $1.received) }
    }

    /// "Sam 12 · Alex 4 · Jo 0. Jo might be missing you." (touches you sent this week).
    func balanceSummary() -> String? {
        let rows = balance()
        guard rows.count > 1 else { return nil }
        let list = rows.map { "\($0.partner.displayName) \($0.sent)" }.joined(separator: " · ")
        let lowest = rows.min { $0.sent < $1.sent }!
        let highest = rows.max { $0.sent < $1.sent }!
        if highest.sent > 0, lowest.sent * 3 < highest.sent {
            return "You reached out: \(list). \(lowest.partner.displayName) might be missing you 💛"
        }
        return "You reached out: \(list). Nicely balanced 💞"
    }
}
