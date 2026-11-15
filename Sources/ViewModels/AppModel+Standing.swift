import Foundation
import SwiftUI
import UserNotifications

/// Set when the check-in reminder is tapped, so Where we stand opens straight onto the update.
enum StandLink {
    static var openUpdate = false
}

// MARK: - Reading and writing a scope

extension TogetherStore {
    /// The live items of a scope: one pair space's list, or (for a group) the union of the
    /// group's list across every pair space with its members.
    func stand<T: StandGrouped>(_ scope: StandScope, _ pair: KeyPath<TogetherSpace, [T]?>,
                                _ group: KeyPath<TogetherSpace, [T]?>) -> [T] {
        guard let key = scope.groupKey else { return syncLive(space(scope.bondID)[keyPath: pair]) }
        return groupUnion(scope.bondIDs, key, group).filter { !$0.deleted }
    }

    /// Every item (tombstones too) tagged `key` in the group lists of `bondIDs`.
    func groupUnion<T: StandGrouped>(_ bondIDs: [String], _ key: String, _ group: KeyPath<TogetherSpace, [T]?>) -> [T] {
        var all: [T] = []
        for b in bondIDs {
            all = TogetherSpace.mergeItems(all, (space(b)[keyPath: group] ?? []).filter { $0.groupKey == key })
        }
        return all
    }
}

extension AppModel {
    // MARK: Scopes

    /// Where we stand with one partner.
    func standScope(_ bondID: String?) -> StandScope {
        StandScope(bondIDs: bondID.map { [$0] } ?? [], groupKey: nil, me: myRole(bondID))
    }

    /// Where we stand with everyone in a group.
    func standScope(_ group: StandGroup) -> StandScope {
        StandScope(bondIDs: group.bondIDs, groupKey: group.key, me: StandPeople.myID)
    }

    /// Changes a scope's list and sends it. For a group, the change is made once to the union
    /// and written into every member's pair space, so they all end up the same. `note` goes
    /// to each partner who hasn't paused (and whose side isn't paused).
    func standEdit<T: StandGrouped>(_ scope: StandScope, note: String? = nil,
                                    _ pair: WritableKeyPath<TogetherSpace, [T]?>,
                                    _ group: WritableKeyPath<TogetherSpace, [T]?>,
                                    _ change: (inout [T]?) -> Void) {
        if let key = scope.groupKey {
            var list: [T]? = together.groupUnion(scope.bondIDs, key, group)
            change(&list)
            let updated = list ?? []
            for b in scope.bondIDs {
                together.edit(b, note: note.flatMap { standNoteAllowed(b) ? $0 : nil }) { s in
                    s[keyPath: group] = TogetherSpace.mergeOptional(s[keyPath: group], updated)
                }
            }
        } else if let b = scope.bondID {
            together.edit(b, note: note.flatMap { standNoteAllowed(b) ? $0 : nil }) { change(&$0[keyPath: pair]) }
        }
    }

    func standWishes(_ scope: StandScope) -> [StandWish] { together.stand(scope, \.standWishes, \.standGroupWishes) }
    func standPromises(_ scope: StandScope) -> [StandPromise] { together.stand(scope, \.standPromises, \.standGroupPromises) }
    func standMarks(_ scope: StandScope) -> [StandMark] { together.stand(scope, \.standMarks, \.standGroupMarks) }

    /// Sets a mark (a newer one with the same id replaces the old).
    func setStandMark(_ scope: StandScope, _ mark: StandMark, note: String? = nil) {
        standEdit(scope, note: note, \.standMarks, \.standGroupMarks) { list in
            var l = list ?? []
            var m = mark
            m.edited = Date()
            if let i = l.firstIndex(where: { $0.id == mark.id }) { m.created = l[i].created; l[i] = m } else { l.append(m) }
            list = l
        }
    }

    func clearStandMark(_ scope: StandScope, _ id: UUID, note: String? = nil) {
        standEdit(scope, note: note, \.standMarks, \.standGroupMarks) { syncDelete(&$0, id) }
    }

    // MARK: Pair state

    /// The other one in a pair.
    func standThem(_ bondID: String?) -> String { myRole(bondID) == "A" ? "B" : "A" }

    func standReadings(_ bondID: String?, by role: String) -> [StandReading] {
        syncLive(together.space(bondID).standReadings).filter { $0.by == role }.sorted { $0.created < $1.created }
    }

    func standLatest(_ bondID: String?, by role: String) -> StandReading? { standReadings(bondID, by: role).last }

    func standPaused(_ bondID: String?, _ role: String) -> Bool {
        standMarks(standScope(bondID)).live(.pause).contains { $0.by == role && $0.value == "on" }
    }

    /// Either of you has paused.
    func standAnyPaused(_ bondID: String?) -> Bool {
        standPaused(bondID, "A") || standPaused(bondID, "B")
    }

    func standQuiet(_ bondID: String?) -> Bool {
        standMarks(standScope(bondID)).live(.quiet).contains { $0.value == "on" }
    }

    /// The shared check-in rhythm in days (0 = off).
    func standRhythm(_ bondID: String?) -> Int {
        standMarks(standScope(bondID)).live(.rhythm).first.flatMap { Int($0.value) } ?? StandRhythm.default
    }

    /// A partner hears about a change only while neither of you has paused and Where we
    /// stand is on.
    func standNoteAllowed(_ bondID: String) -> Bool { Feature.stand.isOn && !standAnyPaused(bondID) }

    /// When your next check-in is due: the rhythm after your last reading (or a moved date).
    /// Nil while off, paused, in a quiet season, or before your first reading.
    func standNextCheckIn(_ bondID: String?) -> Date? {
        guard let bondID, Feature.stand.isOn, !standAnyPaused(bondID), !standQuiet(bondID) else { return nil }
        let every = standRhythm(bondID)
        guard every > 0, let last = standLatest(bondID, by: myRole(bondID)),
              var next = Calendar.current.date(byAdding: .day, value: every, to: last.created) else { return nil }
        if let moved = UserDefaults.standard.object(forKey: "stand.moved.\(bondID)") as? Date, moved > last.created {
            next = max(next, moved)
        }
        return next
    }

    /// Moves your check-in on by a few days (from a rough day).
    func standMoveCheckIn(_ bondID: String?, days: Int = 3) {
        guard let bondID else { return }
        let from = max(standNextCheckIn(bondID) ?? Date(), Date())
        UserDefaults.standard.set(Calendar.current.date(byAdding: .day, value: days, to: from), forKey: "stand.moved.\(bondID)")
        scheduleStandReminders()
    }

    /// Your latest mood check-in (from the last day) was a low one.
    var standMoodLow: Bool {
        guard Feature.stress.isOn, let last = battery.entries.last, Date().timeIntervalSince(last.at) < 24 * 3600 else { return false }
        return ["low", "stressed", "overwhelmed"].contains(last.level)
    }

    /// The name to show for someone in a scope: "You", the partner, or a group member.
    func standName(_ who: String, _ scope: StandScope) -> String {
        if who == scope.me { return "You" }
        if scope.isGroup {
            let known = StandPeople.known()
            if let bond = scope.bondIDs.first(where: { known[$0]?.personID == who }) {
                return partners.first { $0.id == bond }?.displayName ?? "Someone"
            }
            return "Someone"
        }
        return partners.first { $0.id == scope.bondID }?.displayName ?? "Your partner"
    }

    /// Everyone else in a scope ("B", or the other members' person ids).
    func standOthers(_ scope: StandScope) -> [String] {
        guard scope.isGroup else { return [scope.me == "A" ? "B" : "A"] }
        let known = StandPeople.known()
        return scope.bondIDs.compactMap { known[$0]?.personID }
    }

    // MARK: Saving a reading

    /// Saves a new reading of the meter. The number and note go only to this phone unless
    /// you share them.
    func saveStandReading(_ bondID: String?, closeness: Int, note: String, styles: [String], happiness: StandHappiness,
                          working: [String], moreOf: [String], lessOf: [String], pace: StandPace, share: Bool) {
        guard let bondID else { return }
        var r = StandReading(by: myRole(bondID), closeness: share ? closeness : nil, band: StandReading.band(closeness),
                             note: share && !note.isEmpty ? note : nil, styles: styles, happiness: happiness.rawValue,
                             working: working, moreOf: moreOf, lessOf: lessOf, pace: pace.rawValue)
        r.created = Date()
        StandPrivate.set(.init(closeness: closeness, note: note), for: r.id)
        UserDefaults.standard.set(share, forKey: "stand.share.\(bondID)")
        UserDefaults.standard.removeObject(forKey: "stand.moved.\(bondID)")
        together.edit(bondID) { syncAppend(&$0.standReadings, r) }
    }

    /// "Share my number": applies to your latest reading at once, and to new ones.
    func setStandShare(_ bondID: String?, _ on: Bool) {
        guard let bondID else { return }
        UserDefaults.standard.set(on, forKey: "stand.share.\(bondID)")
        guard let last = standLatest(bondID, by: myRole(bondID)) else { return }
        let exact = StandPrivate.closeness(last), note = StandPrivate.note(last)
        together.edit(bondID) { s in
            syncUpdate(&s.standReadings, last.id) { r in
                r.closeness = on ? exact : nil
                r.note = on && !note.isEmpty ? note : nil
            }
        }
    }

    func standSharing(_ bondID: String?) -> Bool {
        bondID.map { UserDefaults.standard.bool(forKey: "stand.share.\($0)") } ?? false
    }

    // MARK: Seen and mutual reveal

    /// Marks the wishes and promises the others made as seen by me ("Seen" on their side).
    /// Only that it was seen: never when, or for how long.
    func markStandSeen(_ scope: StandScope) {
        guard Feature.stand.isOn, scope.isGroup || !standAnyPaused(scope.bondID) else { return }
        let seen = Set(standMarks(scope).live(.seen).filter { $0.by == scope.me }.compactMap(\.item))
        let wishes = standWishes(scope).filter { $0.by != scope.me && !$0.isHidden && !seen.contains($0.id) }.map(\.id)
        let promises = standPromises(scope).filter { $0.by != scope.me && !seen.contains($0.id) }.map(\.id)
        let ids = wishes + promises
        guard !ids.isEmpty else { return }
        standEdit(scope, \.standMarks, \.standGroupMarks) { list in
            for id in ids { syncAppend(&list, StandMark(.seen, item: id, by: scope.me, groupKey: scope.groupKey)) }
        }
    }

    /// When both of you hold a hidden wish with the same keyed hash, both become open wishes
    /// marked "You both want this". Either phone can do it: both hold the bond code.
    func matchStandWishes(_ bondID: String?) {
        guard let bondID, Feature.stand.isOn else { return }
        let me = myRole(bondID)
        let hidden = syncLive(together.space(bondID).standWishes).filter { $0.isHidden }
        let mine = hidden.filter { $0.by == me }, theirs = hidden.filter { $0.by != me }
        var pairs: [(StandWish, StandWish, StandLibraryItem)] = []
        for w in mine {
            guard let t = theirs.first(where: { $0.hidden == w.hidden }),
                  let item = w.hidden.flatMap({ StandLibrary.reveal($0, bondCode: bondID) }) else { continue }
            pairs.append((w, t, item))
        }
        guard !pairs.isEmpty else { return }
        together.edit(bondID, note: standNoteAllowed(bondID) ? "found something you both want in Where we stand 💞" : nil) { s in
            for (w, t, item) in pairs {
                for id in [w.id, t.id] {
                    syncUpdate(&s.standWishes, id) { x in
                        x.both = true; x.title = item.title; x.library = item.id; x.change = item.change
                    }
                }
            }
        }
    }

    // MARK: Promises

    /// Shares a promise with a date onto the poly calendar: the only way anything leaves
    /// Where we stand.
    func shareStandPromiseToCalendar(_ scope: StandScope, _ promise: StandPromise) {
        guard let due = promise.due, promise.event == nil else { return }
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: due) ?? due
        var first: UUID?
        for b in scope.bondIDs {
            let e = CalendarEvent(by: myRole(b), title: promise.title, start: start, end: start.addingTimeInterval(3600),
                                  with: scope.isGroup ? "All of us" : "Us", emoji: "🤝")
            if first == nil { first = e.id }
            together.edit(b, note: standNoteAllowed(b) ? "added a promise to your calendar 📅" : nil) { syncAppend(&$0.events, e) }
        }
        standEdit(scope, \.standPromises, \.standGroupPromises) { list in syncUpdate(&list, promise.id) { p in p.event = first } }
    }

    // MARK: Groups

    /// A partner's profile told us their person id and links.
    func noteStandPerson(bondID: String, personID: String?, links: [String]?) {
        guard personID != nil || links != nil else { return }
        var known = StandPeople.known()
        var k = known[bondID] ?? StandPeople.Known()
        if let personID { k.personID = personID }
        if let links { k.links = links }
        guard known[bondID] != k else { return }
        known[bondID] = k
        StandPeople.saveKnown(known)
    }

    /// Works out my links (hashes of my partners' person ids) and, when they changed, sends
    /// my profile again so partners learn them.
    func refreshStandLinks() async {
        guard Feature.stand.isOn else { return }
        let known = StandPeople.known()
        let links = cloudPartners.filter { !$0.bond.pending }.compactMap { known[$0.id]?.personID }
            .map(StandPeople.linkHash).sorted()
        guard links != StandPeople.myLinks else { return }
        StandPeople.myLinks = links
        await publishProfile()
    }

    /// The groups I'm in: sets of my partners who are all bonded with each other (each lists
    /// the others' hashes). Only the largest such sets count (a quad, not the triads in it).
    func standGroups() -> [StandGroup] {
        guard Feature.stand.isOn else { return [] }
        let known = StandPeople.known()
        var people: [(bond: String, id: String, links: Set<String>)] = []
        for p in cloudPartners where !p.bond.pending {
            guard let k = known[p.id], let id = k.personID, !people.contains(where: { $0.id == id }) else { continue }
            people.append((p.id, id, Set(k.links ?? [])))
        }
        let n = min(people.count, 12)
        guard n >= 2 else { return [] }
        func linked(_ i: Int, _ j: Int) -> Bool {
            people[i].links.contains(StandPeople.linkHash(people[j].id)) && people[j].links.contains(StandPeople.linkHash(people[i].id))
        }
        var cliques: [Int] = []
        for mask in 1..<(1 << n) where mask.nonzeroBitCount >= 2 {
            let members = (0..<n).filter { mask & (1 << $0) != 0 }
            var ok = true
            outer: for a in members.indices { for b in members.indices where b > a {
                if !linked(members[a], members[b]) { ok = false; break outer }
            } }
            if ok { cliques.append(mask) }
        }
        let maximal = cliques.filter { m in !cliques.contains { $0 != m && $0 & m == m } }
        return maximal.map { mask in
            let members = (0..<n).filter { mask & (1 << $0) != 0 }
            let ids = members.map { people[$0].id }
            return StandGroup(key: StandPeople.groupKey(ids + [StandPeople.myID]), members: ids, bondIDs: members.map { people[$0].bond })
        }
    }

    /// For each group, unions its items across all its pair spaces and writes the union back
    /// into each, so every member's copy converges. Items dedupe by id with the usual rules.
    func syncStandGroups() {
        for g in standGroups() {
            let wishes = together.groupUnion(g.bondIDs, g.key, \.standGroupWishes)
            let promises = together.groupUnion(g.bondIDs, g.key, \.standGroupPromises)
            let marks = together.groupUnion(g.bondIDs, g.key, \.standGroupMarks)
            for b in g.bondIDs {
                together.edit(b) { s in
                    if !wishes.isEmpty { s.standGroupWishes = TogetherSpace.mergeOptional(s.standGroupWishes, wishes) }
                    if !promises.isEmpty { s.standGroupPromises = TogetherSpace.mergeOptional(s.standGroupPromises, promises) }
                    if !marks.isEmpty { s.standGroupMarks = TogetherSpace.mergeOptional(s.standGroupMarks, marks) }
                }
            }
        }
    }

    // MARK: Reminders

    /// Local reminders for Where we stand: the check-in, three days before a promise, on a
    /// promise's day, and when a "Not yet" wish can come back. None during a quiet season
    /// or a pause. Rebuilt whenever the spaces change.
    func scheduleStandReminders() {
        guard !Self.isDemo else { return }
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        let now = Date()
        var requests: [UNNotificationRequest] = []
        func add(_ id: String, _ bondID: String, at fire: Date, title: String, body: String) {
            guard fire > now.addingTimeInterval(60) else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = TouchNotification.partnerCategory
            content.threadIdentifier = "stand"
            content.userInfo = [TouchNotification.Key.bond: bondID]
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            requests.append(UNNotificationRequest(identifier: id, content: content,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false)))
        }
        func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        if Feature.stand.isOn, NotificationKind.standReminders.isOn {
            for p in cloudPartners where !p.bond.pending && !standAnyPaused(p.id) && !standQuiet(p.id) {
                let name = p.displayName
                let scope = standScope(p.id)
                // The check-in.
                if let next = standNextCheckIn(p.id) {
                    add("stand-checkin-\(p.id)", p.id, at: Self.inWindow(at(max(next, now), 19)),
                        title: "Where do you stand with \(name)?",
                        body: standMoodLow ? "You're having a rough day. Want to move the check-in?" : "2 minutes.")
                }
                standPromiseReminders(scope, bondID: p.id, add: add, at: at)
            }
            for g in standGroups() where !g.bondIDs.contains(where: { standAnyPaused($0) || standQuiet($0) }) {
                guard let first = g.bondIDs.first else { continue }
                standPromiseReminders(standScope(g), bondID: first, add: add, at: at)
            }
        }

        center.getPendingNotificationRequests { old in
            center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier).filter { $0.hasPrefix("stand-") })
            requests.prefix(16).forEach { center.add($0) }
        }
    }

    /// The promise and come-back reminders for one scope (added through `add`).
    private func standPromiseReminders(_ scope: StandScope, bondID: String,
                                       add: (String, String, Date, String, String) -> Void,
                                       at: (Date, Int, Int) -> Date) {
        let cal = Calendar.current
        for promise in standPromises(scope) where promise.status == .open {
            guard let due = promise.due else { continue }
            if let before = cal.date(byAdding: .day, value: -3, to: due) {
                add("stand-promise-\(promise.id)-3", bondID, at(before, 10, 30),
                    "\(promise.title) is coming up", "Still on?")
            }
            add("stand-promise-\(promise.id)-0", bondID, at(due, 20, 30),
                promise.title, "This one slipped by. Renew, change it, or let it go?")
        }
        // A wish you made that someone said "Not yet" to: a quiet note when it can come back.
        let marks = standMarks(scope).live(.answer)
        for w in standWishes(scope) where w.by == scope.me {
            for m in marks where m.item == w.id && m.value == StandAnswer.notYet.rawValue {
                guard let until = m.until else { continue }
                add("stand-back-\(w.id)-\(m.by.prefix(8))", bondID, at(until, 11, 0),
                    "A wish can come back", "\"\(w.title)\" can come up again, whenever you're ready.")
            }
        }
    }

    // MARK: Export before unbonding

    /// A readable copy of Where we stand with one partner (Markdown, plus JSON alongside):
    /// your meter history, wishes, promises and the kept moments. Files in a temporary folder.
    func standExport(_ bondID: String) -> [URL] {
        let space = together.space(bondID)
        let me = myRole(bondID), them = standThem(bondID)
        let name = partners.first { $0.id == bondID }?.displayName ?? "Partner"
        let scope = standScope(bondID)
        let day = { (d: Date) in d.formatted(date: .abbreviated, time: .omitted) }
        func who(_ r: String) -> String { r == me ? "You" : name }

        var md = "# Where we stand: you & \(name)\n\nExported \(day(Date())).\n"
        if let since = space.togetherSince { md += "Together since \(day(since)).\n" }

        md += "\n## Your meter\n\n"
        let mine = standReadings(bondID, by: me)
        if mine.isEmpty { md += "No readings yet.\n" }
        for r in mine {
            let theirs = standReadings(bondID, by: them).last { $0.created <= r.created }
            md += "- **\(day(r.created))**: closeness \(StandPrivate.closeness(r))/10, \(r.happy.title.lowercased()), \(r.paceValue.title.lowercased())"
            if !r.styles.isEmpty { md += ", " + r.styles.joined(separator: ", ") }
            md += ". \(StandAlignment.of(r, theirs).title).\n"
            let note = StandPrivate.note(r)
            if !note.isEmpty { md += "  - \(note)\n" }
            if !r.working.isEmpty { md += "  - Working: \(r.working.joined(separator: "; "))\n" }
            if !r.moreOf.isEmpty { md += "  - More of: \(r.moreOf.joined(separator: "; "))\n" }
            if !r.lessOf.isEmpty { md += "  - Less of: \(r.lessOf.joined(separator: "; "))\n" }
        }
        if let t = standLatest(bondID, by: them) {
            md += "\n\(name)'s latest: \(t.styles.joined(separator: ", "))"
            if let c = t.closeness { md += ", closeness \(c)/10" }
            md += ".\n"
        }

        let marks = standMarks(scope)
        md += "\n## Wishes\n\n"
        let wishes = standWishes(scope).filter { !$0.isHidden || $0.by == me }
        if wishes.isEmpty { md += "None.\n" }
        for w in wishes {
            let title = w.isHidden ? (w.hidden.flatMap { StandLibrary.reveal($0, bondCode: bondID)?.title } ?? "A private wish") + " (only shown if they want it too)" : w.title
            md += "- \(w.emoji) \(title): \(w.both ? "you both want this" : "from \(who(w.by))"), \(w.matters ? "this matters" : "would be lovely")\n"
            for a in marks.live(.answer) where a.item == w.id {
                let answer = StandAnswer(rawValue: a.value)?.title ?? a.value
                md += "  - \(who(a.by)): \(answer)\(a.until.map { " (can come back \(day($0)))" } ?? "")\n"
            }
        }

        let promises = standPromises(scope)
        md += "\n## Promises\n\n"
        if promises.isEmpty { md += "None.\n" }
        for p in promises {
            md += "- \(p.title): made by \(who(p.by)), \(p.status.title.lowercased())\(p.due.map { ", for \(day($0))" } ?? "")\n"
            if !p.note.isEmpty { md += "  - \(p.note)\n" }
        }

        md += "\n## What we've done for each other\n\n"
        let kept = promises.filter { $0.status == .kept }
        if kept.isEmpty { md += "Nothing yet.\n" }
        for p in kept {
            md += "- \(p.title) (\(who(p.by)), \(day(p.stateAt ?? p.edited)))\n"
            for t in marks.live(.thanks) where t.item == p.id { md += "  - \(who(t.by)): \(t.value)\n" }
        }

        struct Export: Encodable {
            let partner: String
            let exported: Date
            let myReadings: [StandReading]
            let theirReadings: [StandReading]
            let wishes: [StandWish]
            let promises: [StandPromise]
            let thanks: [StandMark]
        }
        let myExact = mine.map { r -> StandReading in
            var x = r; x.closeness = StandPrivate.closeness(r); let n = StandPrivate.note(r); x.note = n.isEmpty ? nil : n; return x
        }
        let export = Export(partner: name, exported: Date(), myReadings: myExact, theirReadings: standReadings(bondID, by: them),
                            wishes: wishes, promises: promises, thanks: marks.live(.thanks))

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WhereWeStand-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = name.filter { $0.isLetter || $0.isNumber || $0 == " " }
        let base = "Where we stand - \(safe.isEmpty ? "partner" : safe)"
        var urls: [URL] = []
        let mdURL = folder.appendingPathComponent(base + ".md")
        if (try? md.write(to: mdURL, atomically: true, encoding: .utf8)) != nil { urls.append(mdURL) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonURL = folder.appendingPathComponent(base + ".json")
        if let data = try? encoder.encode(export), (try? data.write(to: jsonURL)) != nil { urls.append(jsonURL) }
        return urls
    }
}
