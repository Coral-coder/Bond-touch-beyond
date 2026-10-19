import Foundation
import SwiftUI
import UserNotifications

/// The Us space for each partner (see `TogetherSpace`), kept on this phone and synced with
/// the partner's phone through iCloud. Edits save at once and go up a moment later (a quick
/// run of edits sends once), with a silent push so the partner's phone picks them up.
@MainActor
final class TogetherStore: ObservableObject {
    @Published private(set) var spaces: [String: TogetherSpace] = [:]
    @Published private(set) var boards: [String: Whiteboard] = [:]

    /// Called (debounced) with a bond whose space or board changed here.
    var onLocalChange: ((String, _ space: Bool, _ board: Bool) -> Void)?

    private var pending: [String: (space: Bool, board: Bool)] = [:]
    private var flush: Task<Void, Never>?

    init() {
        spaces = Self.load([String: TogetherSpace].self, "together.json") ?? [:]
        boards = Self.load([String: Whiteboard].self, "whiteboards.json") ?? [:]
    }

    func space(_ bondID: String?) -> TogetherSpace { bondID.flatMap { spaces[$0] } ?? TogetherSpace() }
    func board(_ bondID: String?) -> Whiteboard { bondID.flatMap { boards[$0] } ?? Whiteboard() }

    /// What changed, per bond, for the partner's notification ("added a to-do").
    private var notes: [String: [String]] = [:]

    /// Changes the space for `bondID` here, and sends it. `note` (e.g. "added a to-do ✅")
    /// becomes a notification on the partner's phone.
    func edit(_ bondID: String?, note: String? = nil, _ change: (inout TogetherSpace) -> Void) {
        guard let bondID else { return }
        var s = space(bondID)
        change(&s)
        guard s != spaces[bondID] else { return }
        spaces[bondID] = s
        Self.save(spaces, "together.json")
        if let note { notes[bondID, default: []].append(note) }
        schedule(bondID, space: true)
    }

    /// The notes collected since the last send for `bondID`, cleared.
    func takeNotes(_ bondID: String) -> [String] {
        defer { notes[bondID] = nil }
        return notes[bondID] ?? []
    }

    func editBoard(_ bondID: String?, _ change: (inout Whiteboard) -> Void) {
        guard let bondID else { return }
        var b = board(bondID)
        change(&b)
        guard b != boards[bondID] else { return }
        boards[bondID] = b
        Self.save(boards, "whiteboards.json")
        schedule(bondID, board: true)
    }

    /// Merges the partner's copies in. Returns true when something here changed.
    @discardableResult
    func mergeRemote(space remote: TogetherSpace?, board remoteBoard: Whiteboard?, bondID: String) -> Bool {
        var changed = false
        if let remote {
            var s = space(bondID)
            s.merge(remote)
            if s != spaces[bondID] { spaces[bondID] = s; Self.save(spaces, "together.json"); changed = true }
            // If ours has something theirs lacks, send ours back so both end up the same.
            if s != remote { schedule(bondID, space: true) }
        }
        if let remoteBoard {
            var b = board(bondID)
            b.merge(remoteBoard)
            if b != boards[bondID] { boards[bondID] = b; Self.save(boards, "whiteboards.json"); changed = true }
            if b != remoteBoard { schedule(bondID, board: true) }
        }
        return changed
    }

    private func schedule(_ bondID: String, space: Bool = false, board: Bool = false) {
        let p = pending[bondID] ?? (false, false)
        pending[bondID] = (p.space || space, p.board || board)
        flush?.cancel()
        flush = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, !Task.isCancelled else { return }
            let all = self.pending
            self.pending = [:]
            for (id, what) in all { self.onLocalChange?(id, what.space, what.board) }
        }
    }

    // MARK: Files

    private static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Together", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
    }
}

extension AppModel {
    /// "A" if this phone created the bond with `bondID`, else "B".
    func myRole(_ bondID: String?) -> String {
        partners.first { $0.id == bondID }?.bond.isOwner == false ? "B" : "A"
    }

    /// Hooks the Us store up to iCloud. Called once at start.
    func startTogetherSync() {
        together.onLocalChange = { [weak self] bondID, space, board in
            Task { await self?.uploadTogether(bondID, space: space, board: board) }
        }
        scheduleDateReminders()
    }

    private func uploadTogether(_ bondID: String, space: Bool, board: Bool) async {
        guard let partner = cloudPartners.first(where: { $0.id == bondID }) else { return }
        do {
            if space { try await relay.sendSpace(together.space(bondID), bond: partner.bond) }
            if board { try await relay.sendBoard(together.board(bondID), bond: partner.bond) }
            // A visible notification for what changed (it also wakes their app to sync);
            // otherwise just a silent nudge.
            let notes = together.takeNotes(bondID)
            if let last = notes.last {
                await notifyPartner(bondID, notes.count > 1 ? "\(last) and \(notes.count - 1) more update\(notes.count == 2 ? "" : "s")" : last)
            } else if let token = partnerPushTokens[bondID], !token.isEmpty {
                await APNsClient.shared.sendBackground(toDeviceToken: token, extra: ["bl": BondCrypto.locator(forCode: bondID), "us": 1])
            }
        } catch {
            NetLog.shared.log(.fail, "iCloud: Us space not sent", error.localizedDescription)
        }
        if space { scheduleDateReminders() }
    }

    /// A notification on the partner's phone: "Sam added a to-do ✅". Never the content of
    /// notes or chat — just what kind of thing changed.
    func notifyPartner(_ bondID: String?, _ text: String) async {
        guard let bondID else { return }
        let me = store.profile.name.isEmpty ? "Your partner" : store.profile.name
        await pushPartner(bondID: bondID, title: "💞 Us", body: "\(me) \(text)", group: "u", sound: "default")
    }

    /// Battleship: this phone answers the partner's shots at our fleet (which only this phone
    /// knows), and reveals the fleet once the game is over.
    func answerBattleship(_ bondID: String?) {
        guard let bondID, let game = together.space(bondID).battleship,
              let fleet = BattleshipGame.loadFleet(game.id) else { return }
        let me = myRole(bondID), them = me == "A" ? "B" : "A"
        let pending = game.unanswered(against: me)
        guard !pending.isEmpty else { return }
        var hit = Set(game.results(for: them).filter { $0.value != "m" }.keys)
        var answers: [(Int, String)] = []
        for cell in pending {
            let a = BattleshipGame.answer(cell, fleet: fleet, alreadyHit: hit)
            if a != "m" { hit.insert(cell) }
            answers.append((cell, a))
        }
        let last = answers.last?.1 ?? "m"
        let note = last == "m" ? "'s waters: 🌊 miss" : last.hasPrefix("s") ? "'s ship sank 💥🚢" : "'s ship was hit 💥"
        together.edit(bondID, note: note) { s in
            for (cell, a) in answers { s.battleship?.add("res:\(them):\(cell):\(a)") }
            if s.battleship?.winner != nil {
                s.battleship?.add("fleet:\(me):" + fleet.flatMap { $0 }.map(String.init).joined(separator: ","))
            }
        }
    }

    /// Merges what the partner's phone sent (called from the iCloud poll).
    func receiveTogether(space: TogetherSpace?, board: Whiteboard?, bondID: String) {
        guard space != nil || board != nil else { return }
        if together.mergeRemote(space: space, board: board, bondID: bondID), space != nil { scheduleDateReminders() }
        if space?.battleship != nil { answerBattleship(bondID) }
    }

    /// Local reminders for every special date with every partner: on the day at 9:00 and
    /// (if set) some days before. Rebuilt whenever the dates change.
    func scheduleDateReminders() {
        let center = UNUserNotificationCenter.current()
        let names = Dictionary(partners.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        var requests: [UNNotificationRequest] = []
        for (bondID, space) in together.spaces {
            let name = names[bondID] ?? "your partner"
            for d in space.dates where !d.deleted {
                let next = d.next()
                let ordinal = d.ordinalText().map { " — \($0)" } ?? ""
                func add(daysBefore: Int) {
                    guard let day = Calendar.current.date(byAdding: .day, value: -daysBefore, to: next) else { return }
                    var c = Calendar.current.dateComponents([.year, .month, .day], from: day)
                    c.hour = 9
                    guard let fire = Calendar.current.date(from: c), fire > Date() else { return }
                    let content = UNMutableNotificationContent()
                    content.title = daysBefore == 0 ? "Today: \(d.title)" : "\(d.title) in \(daysBefore) day\(daysBefore == 1 ? "" : "s")"
                    content.body = (daysBefore == 0 ? "\(d.kind == .birthday ? "🎂" : "💞") A special day with \(name)" : "Coming up with \(name)") + ordinal
                    content.sound = .default
                    requests.append(UNNotificationRequest(identifier: "date-\(d.id)-\(daysBefore)", content: content,
                                                          trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false)))
                }
                add(daysBefore: 0)
                if d.remindDaysBefore > 0 { add(daysBefore: d.remindDaysBefore) }
            }
        }
        // R.A.D.A.R. check-ins: the day before and on the day, at 9:00.
        for (bondID, space) in together.spaces {
            guard let next = space.radarNext else { continue }
            let name = names[bondID] ?? "your partner"
            for before in [1, 0] {
                guard let day = Calendar.current.date(byAdding: .day, value: -before, to: next) else { continue }
                var c = Calendar.current.dateComponents([.year, .month, .day], from: day)
                c.hour = 9
                guard let fire = Calendar.current.date(from: c), fire > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = before == 0 ? "📡 R.A.D.A.R. with \(name) today" : "📡 R.A.D.A.R. with \(name) tomorrow"
                content.body = "Add anything you want to talk about to the agenda."
                content.sound = .default
                requests.append(UNNotificationRequest(identifier: "date-radar-\(bondID)-\(before)", content: content,
                                                      trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false)))
            }
        }
        center.getPendingNotificationRequests { old in
            center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier).filter { $0.hasPrefix("date-") })
            requests.prefix(60).forEach { center.add($0) }
        }
    }
}
