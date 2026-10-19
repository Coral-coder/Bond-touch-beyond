import Foundation

/// Everything two partners share about themselves as a couple: when they got together,
/// their special dates, what each likes, a shared to-do list, shared notes and a chess game.
/// Both phones keep a full copy and exchange it (sealed) through iCloud; copies merge item
/// by item — the newer edit wins and deletions are kept as tombstones — so either of you can
/// change anything, even offline.
struct TogetherSpace: Codable, Equatable {
    var togetherSince: Date?
    var togetherSinceEdited: Date = .distantPast
    var dates: [SpecialDate] = []
    var likes: [Preference] = []
    var todos: [TodoItem] = []
    var notes: [SharedNote] = []
    var chess: ChessGame?

    /// Combines the partner's copy into ours.
    mutating func merge(_ other: TogetherSpace) {
        if other.togetherSinceEdited > togetherSinceEdited {
            togetherSince = other.togetherSince
            togetherSinceEdited = other.togetherSinceEdited
        }
        dates = Self.mergeItems(dates, other.dates)
        likes = Self.mergeItems(likes, other.likes)
        todos = Self.mergeItems(todos, other.todos)
        notes = Self.mergeItems(notes, other.notes)
        chess = ChessGame.merge(chess, other.chess)
    }

    static func mergeItems<T: SyncItem>(_ a: [T], _ b: [T]) -> [T] {
        var byID: [UUID: T] = [:]
        for item in a + b {
            if let have = byID[item.id], have.edited >= item.edited { continue }
            byID[item.id] = item
        }
        return byID.values.sorted { $0.created < $1.created }
    }

    /// How long you've been together, as "1 year, 3 months, 12 days".
    static func durationText(since: Date, to now: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: since, to: now)
        var parts: [String] = []
        if let y = c.year, y > 0 { parts.append("\(y) year\(y == 1 ? "" : "s")") }
        if let m = c.month, m > 0 { parts.append("\(m) month\(m == 1 ? "" : "s")") }
        let d = c.day ?? 0
        if d > 0 || parts.isEmpty { parts.append("\(d) day\(d == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    /// Whole days together.
    static func days(since: Date, to now: Date = Date()) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: since), to: cal.startOfDay(for: now)).day ?? 0
    }
}

/// Something both phones edit: identified, with when it was made, last changed and deleted.
protocol SyncItem: Codable, Identifiable where ID == UUID {
    var id: UUID { get }
    var created: Date { get }
    var edited: Date { get set }
    var deleted: Bool { get set }
}

/// An anniversary, a birthday or any date worth remembering. Yearly ones come back every year.
struct SpecialDate: SyncItem, Equatable {
    enum Kind: String, Codable, CaseIterable { case anniversary, birthday, other
        var icon: String {
            switch self { case .anniversary: return "heart.circle.fill"; case .birthday: return "gift.fill"; case .other: return "star.fill" }
        }
        var title: String { rawValue.capitalized }
    }
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var title: String
    var date: Date
    var kind: Kind
    var yearly = true
    /// Remind on the day, and this many days before (0 = only on the day).
    var remindDaysBefore = 7

    /// The next time it comes round (today counts), or the date itself if it isn't yearly.
    func next(after now: Date = Date()) -> Date {
        guard yearly else { return date }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var c = cal.dateComponents([.month, .day], from: date)
        c.year = cal.component(.year, from: today)
        var d = cal.date(from: c) ?? date
        if d < today { c.year! += 1; d = cal.date(from: c) ?? date }
        return d
    }

    /// Days until the next one (0 = today).
    func daysUntil(_ now: Date = Date()) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: next(after: now))).day ?? 0
    }

    /// Which time it'll be ("3rd anniversary", "turns 29"), for yearly dates with a past start.
    func ordinalText(now: Date = Date()) -> String? {
        guard yearly else { return nil }
        let n = Calendar.current.component(.year, from: next(after: now)) - Calendar.current.component(.year, from: date)
        guard n > 0 else { return nil }
        switch kind {
        case .birthday: return "turns \(n)"
        case .anniversary: return "\(n)\(Self.suffix(n)) anniversary"
        case .other: return "\(n)\(Self.suffix(n)) time"
        }
    }

    private static func suffix(_ n: Int) -> String {
        if (11...13).contains(n % 100) { return "th" }
        switch n % 10 { case 1: return "st"; case 2: return "nd"; case 3: return "rd"; default: return "th" }
    }
}

/// Something one of you likes (or doesn't): "Favourite flowers — peonies".
struct Preference: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    /// Whose it is: "A" (who created the bond) or "B".
    var owner: String
    var label: String
    var value: String
}

struct TodoItem: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var text: String
    var done = false
    /// "A" or "B": who added it.
    var by: String
}

struct SharedNote: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var title: String
    var body: String
}

/// One chess game: the moves so far (as from–to squares, e.g. "e2e4", "e7e8q"). The bond's
/// creator plays white. A newer game replaces an older one; within a game the longer move
/// list wins (each phone only ever adds its own moves).
struct ChessGame: Codable, Equatable {
    var id = UUID()
    var started = Date()
    var moves: [String] = []
    var edited = Date()
    /// Set when someone resigns: "A" or "B".
    var resigned: String?

    static func merge(_ a: ChessGame?, _ b: ChessGame?) -> ChessGame? {
        guard let a else { return b }
        guard let b else { return a }
        if a.id != b.id { return a.started >= b.started ? a : b }
        if a.moves.count != b.moves.count { return a.moves.count > b.moves.count ? a : b }
        return a.edited >= b.edited ? a : b
    }
}

/// The shared whiteboard: strokes from both of you. Clearing removes everything drawn before.
struct Whiteboard: Codable, Equatable {
    struct Stroke: Codable, Equatable, Identifiable {
        var id = UUID()
        var at = Date()
        var rgb: Int
        var width: Double
        /// Points in 0…1 board coordinates, flattened [x0, y0, x1, y1, …], 3 decimals.
        var points: [Double]
        var by: String
    }
    var strokes: [Stroke] = []
    var clearedAt: Date = .distantPast
    /// Strokes taken back with Undo (kept so the other copy drops them too).
    var removed: [UUID] = []

    mutating func merge(_ other: Whiteboard) {
        clearedAt = max(clearedAt, other.clearedAt)
        removed = Array(Set(removed + other.removed)).suffix(400).map { $0 }
        var seen = Set(strokes.map(\.id))
        for s in other.strokes where !seen.contains(s.id) { strokes.append(s); seen.insert(s.id) }
        let gone = Set(removed)
        strokes = strokes.filter { $0.at > clearedAt && !gone.contains($0.id) }.sorted { $0.at < $1.at }
        if strokes.count > 600 { strokes = Array(strokes.suffix(600)) }
    }
}
