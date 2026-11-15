import CryptoKit
import Foundation

// Where we stand: a gentle meter of how each of you feels about the relationship, the
// wishes either of you has for it, the promises you make each other, and a regular check-in.
// Everything is a list of `SyncItem`s in `TogetherSpace` (so it merges item by item and is
// sealed like the rest of Us). Group items (a triad, a quad) live in their own lists, tagged
// with the group's key, in every pair space between the group's members.

// MARK: The meter

/// How you feel about where things are. No answer is better than another: content is
/// content, whatever the shape of the relationship.
enum StandHappiness: String, Codable, CaseIterable, Identifiable {
    case content, more, less, unsure
    var id: String { rawValue }
    var title: String {
        switch self {
        case .content: return "Content"
        case .more: return "Want more"
        case .less: return "Want less"
        case .unsure: return "Not sure"
        }
    }
    var emoji: String {
        switch self { case .content: return "😌"; case .more: return "🌱"; case .less: return "🍃"; case .unsure: return "🤔" }
    }
}

/// How fast you like things to move.
enum StandPace: String, Codable, CaseIterable, Identifiable {
    case slow, steady, ready
    var id: String { rawValue }
    var title: String {
        switch self {
        case .slow: return "I like things slow"
        case .steady: return "Steady"
        case .ready: return "Ready when you are"
        }
    }
}

/// The styles to pick from. None ranks above another.
enum StandStyles {
    static let shape = ["Anchor", "Nesting", "Non-nesting", "Primary", "Secondary", "Long-distance", "Comet"]
    static let kind = ["Partners", "Dating", "Casual", "FWB", "Queerplatonic", "Play partner", "New"]
    static var all: [String] { shape + kind }

    /// Styles both of you picked (case-insensitive), in the order the first list has them.
    static func overlap(_ a: [String], _ b: [String]) -> [String] {
        let theirs = Set(b.map { $0.lowercased() })
        return a.filter { theirs.contains($0.lowercased()) }
    }
}

/// One reading of the meter by one of you. Each update adds a reading, so the history is
/// simply all of them.
///
/// The exact closeness number and the note stay on your phone unless "Share my number" is
/// on; the partner's phone only ever gets `band` (1–5), enough for the alignment.
struct StandReading: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    /// "A" or "B".
    var by: String
    /// 1–10, only when shared.
    var closeness: Int?
    /// The closeness in pairs: 1 (1–2) … 5 (9–10).
    var band: Int
    /// The one-line note, only when shared.
    var note: String?
    var styles: [String] = []
    var happiness: String = StandHappiness.content.rawValue
    var working: [String] = []
    var moreOf: [String] = []
    var lessOf: [String] = []
    var pace: String = StandPace.steady.rawValue

    var happy: StandHappiness { StandHappiness(rawValue: happiness) ?? .unsure }
    var paceValue: StandPace { StandPace(rawValue: pace) ?? .steady }
    var shared: Bool { closeness != nil }

    static func band(_ closeness: Int) -> Int { min(5, max(1, (closeness + 1) / 2)) }
}

/// What this phone keeps to itself about your own readings: the exact number and note when
/// you didn't share them.
enum StandPrivate {
    struct Entry: Codable { var closeness: Int; var note: String }
    private static let key = "stand.private"

    static func all() -> [String: Entry] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }
    static func get(_ id: UUID) -> Entry? { all()[id.uuidString] }
    static func set(_ entry: Entry, for id: UUID) {
        var map = all()
        map[id.uuidString] = entry
        if let data = try? JSONEncoder().encode(map) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// My number for one of my readings: shared, kept here, or (from another phone) the band.
    static func closeness(_ r: StandReading) -> Int { r.closeness ?? get(r.id)?.closeness ?? r.band * 2 }
    static func note(_ r: StandReading) -> String { r.note ?? get(r.id)?.note ?? "" }
}

/// The shape the two of you are in, from both closeness bands, both happiness answers and
/// how much your styles overlap. It's about alignment, never height.
enum StandAlignment: String, CaseIterable {
    case goodPlace, growing, easing, checkIn, finding, waiting

    var title: String {
        switch self {
        case .goodPlace: return "You're both in a good place"
        case .growing: return "You'd both like a little more"
        case .easing: return "You'd both like a little more room"
        case .checkIn: return "Worth a check-in"
        case .finding: return "Still finding the words"
        case .waiting: return "Waiting for both of you"
        }
    }

    var emoji: String {
        switch self {
        case .goodPlace: return "💞"; case .growing: return "🌱"; case .easing: return "🍃"
        case .checkIn: return "☕️"; case .finding: return "🤍"; case .waiting: return "⏳"
        }
    }

    /// 0…1, for the history chart: how aligned, not how close.
    var score: Double {
        switch self {
        case .goodPlace: return 1
        case .growing, .easing: return 0.85
        case .finding: return 0.6
        case .checkIn: return 0.45
        case .waiting: return 0
        }
    }

    static func of(_ a: StandReading?, _ b: StandReading?) -> StandAlignment {
        guard let a, let b else { return .waiting }
        let gap = abs(a.band - b.band)
        switch (a.happy, b.happy) {
        case (.content, .content): return gap >= 3 ? .finding : .goodPlace
        case (.more, .more): return .growing
        case (.less, .less): return .easing
        case (.unsure, _), (_, .unsure): return .finding
        default: return .checkIn
        }
    }

    /// A kind line to go with the shape.
    static func detail(_ a: StandReading?, _ b: StandReading?, name: String) -> String {
        let shape = of(a, b)
        guard let a, let b else {
            return a == nil ? "Take two minutes to say where you stand. \(name) won't see your number unless you share it."
                            : "Once \(name) has said where they stand, you'll both see how you line up."
        }
        let same = StandStyles.overlap(a.styles, b.styles)
        let styles: String
        if a.styles.isEmpty || b.styles.isEmpty { styles = "" }
        else if same.isEmpty { styles = " You describe it differently, which is worth a chat." }
        else { styles = " You both call it " + same.prefix(3).joined(separator: ", ") + "." }
        switch shape {
        case .goodPlace: return "You're both content with how things are." + styles
        case .growing: return "You'd both welcome more. Wishes are a good place to start." + styles
        case .easing: return "You'd both like a little more space. That's okay." + styles
        case .checkIn: return "One of you would like a change. A gentle chat could help." + styles
        case .finding: return "Things feel a little different for each of you. No rush." + styles
        case .waiting: return styles
        }
    }
}

// MARK: Wishes

/// A starter wish. Mutual reveal works only with these: custom wording can't match.
struct StandLibraryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let emoji: String
    /// "A change I'd like" rather than "Closer".
    var change = false
}

enum StandLibrary {
    static let all: [StandLibraryItem] = [
        .init(id: "friends", title: "Meet friends", emoji: "🧑‍🤝‍🧑"),
        .init(id: "family", title: "Meet family", emoji: "🏡"),
        .init(id: "kids", title: "Meet kids", emoji: "🧸"),
        .init(id: "weekend", title: "A weekend away", emoji: "🧳"),
        .init(id: "travel", title: "Travel together", emoji: "✈️"),
        .init(id: "overnights", title: "Overnights", emoji: "🌙"),
        .init(id: "iloveyou", title: "Say \"I love you\"", emoji: "💗"),
        .init(id: "key", title: "A key", emoji: "🔑"),
        .init(id: "holidays", title: "Holidays together", emoji: "🎄"),
        .init(id: "movein", title: "Move in", emoji: "📦"),
        .init(id: "pets", title: "Co-parent pets", emoji: "🐾"),
        .init(id: "space", title: "More space", emoji: "🍃", change: true),
        .init(id: "fewerovernights", title: "Fewer overnights", emoji: "🌗", change: true),
    ]

    static func item(_ id: String?) -> StandLibraryItem? { all.first { $0.id == id } }

    /// Lowercased, letters and digits only, single spaces: "Say "I love you"" → "say i love you".
    static func normalize(_ s: String) -> String {
        let kept = s.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// The keyed hash a mutual-reveal wish carries instead of its words: HMAC-SHA256 of the
    /// normalized title, keyed with the bond code.
    static func hiddenHash(_ item: StandLibraryItem, bondCode: String) -> String {
        let key = SymmetricKey(data: Data(bondCode.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(normalize(item.title).utf8), using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    /// Which starter a hidden hash is (only the two people with the bond code can tell).
    static func reveal(_ hash: String, bondCode: String) -> StandLibraryItem? {
        all.first { hiddenHash($0, bondCode: bondCode) == hash }
    }
}

/// Something one or both of you want that isn't there yet.
struct StandWish: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    /// Who wished it: "A"/"B" in a pair, a person id in a group.
    var by: String
    /// Empty while it's a hidden mutual-reveal wish.
    var title: String = ""
    var library: String?
    /// "This matters to me" (otherwise "Would be lovely").
    var matters = false
    /// "A change I'd like" (otherwise "Closer"). Same mechanics, softer words.
    var change = false
    /// Mutual reveal: only the keyed hash, never the words, until you both want it.
    var hidden: String?
    /// You both wanted it (a mutual reveal matched).
    var both = false
    /// The promise made from it.
    var promise: UUID?
    var groupKey: String?

    var isHidden: Bool { hidden != nil && !both }
    var emoji: String { StandLibrary.item(library)?.emoji ?? (change ? "🍃" : "🌱") }
}

/// How someone answered an open wish.
enum StandAnswer: String, CaseIterable, Identifiable {
    case yes, notYet, talk
    var id: String { rawValue }
    var title: String {
        switch self {
        case .yes: return "Yes, let's"
        case .notYet: return "Not yet"
        case .talk: return "Let's talk"
        }
    }
    var emoji: String { switch self { case .yes: return "💞"; case .notYet: return "🌙"; case .talk: return "☕️" } }
}

// MARK: Promises

enum StandPromiseState: String, CaseIterable {
    case open, kept, changed, letGo
    var title: String {
        switch self {
        case .open: return "Open"
        case .kept: return "Kept"
        case .changed: return "Changed"
        case .letGo: return "Let go"
        }
    }
}

/// Something one of you promises, from an agreed wish or on its own.
struct StandPromise: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    /// Who made it: "A"/"B" in a pair, a person id in a group.
    var by: String
    var title: String
    var due: Date?
    var note: String = ""
    var wish: UUID?
    var state: String = StandPromiseState.open.rawValue
    var stateAt: Date?
    /// When changed: the promise this one replaces.
    var replaces: UUID?
    /// The poly-calendar event it was shared as, if it was.
    var event: UUID?
    var groupKey: String?

    var status: StandPromiseState { StandPromiseState(rawValue: state) ?? .open }
    /// Still open and its day has gone by.
    var slipped: Bool {
        guard status == .open, let due else { return false }
        return Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: Date())
    }
}

// MARK: Marks

/// Small facts kept as their own items so two phones never overwrite each other's: who has
/// seen a wish or promise, an answer to a wish, a thank-you for a kept promise, a pause, the
/// quiet season and the check-in rhythm. Each has a stable id from what it's about, so a
/// newer one simply replaces the older.
struct StandMark: SyncItem, Equatable {
    enum Kind: String { case seen, answer, thanks, pause, quiet, rhythm }

    var id: UUID
    var created = Date()
    var edited = Date()
    var deleted = false
    var kind: String
    /// The wish or promise it's about.
    var item: UUID?
    var by: String
    var value: String = ""
    /// For "Not yet": when the wish may come back.
    var until: Date?
    var groupKey: String?

    init(_ kind: Kind, item: UUID? = nil, by: String, value: String = "", until: Date? = nil,
         groupKey: String? = nil, shared: Bool = false) {
        // A shared setting (quiet season, rhythm) has one id for both of you.
        id = Self.stableID(kind.rawValue, item?.uuidString ?? "", shared ? "*" : by, groupKey ?? "")
        self.kind = kind.rawValue
        self.item = item
        self.by = by
        self.value = value
        self.until = until
        self.groupKey = groupKey
    }

    static func stableID(_ parts: String...) -> UUID {
        let d = Array(SHA256.hash(data: Data(parts.joined(separator: "|").utf8)))
        return UUID(uuid: (d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12], d[13], d[14], d[15]))
    }
}

extension Array where Element == StandMark {
    func live(_ kind: StandMark.Kind) -> [StandMark] { filter { !$0.deleted && $0.kind == kind.rawValue } }
}

/// The check-in rhythm choices, in days (0 = off).
enum StandRhythm {
    static let choices = [14, 30, 90, 0]
    static let `default` = 30
    static func title(_ days: Int) -> String {
        switch days {
        case 14: return "Every 2 weeks"
        case 30: return "Monthly"
        case 90: return "Quarterly"
        default: return "Off"
        }
    }
}

// MARK: People and groups

/// Who's who, without exposing anyone's partners: each install has a random person id that
/// only its partners learn (in the sealed profile), plus a list of hashes of its partners'
/// ids. Two of my partners who each list the other's hash are bonded with each other.
enum StandPeople {
    /// Hashed with this fixed app constant, so a hash means nothing without the id.
    private static let linkSalt = "BondTouchBeyond.where-we-stand.links.v1"

    /// This install's person id, made once.
    static var myID: String {
        if let id = UserDefaults.standard.string(forKey: "stand.personID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "stand.personID")
        return id
    }

    /// The hashes of my partners' person ids, as last worked out (sent in my profile).
    static var myLinks: [String] {
        get { UserDefaults.standard.stringArray(forKey: "stand.myLinks") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "stand.myLinks") }
    }

    static func linkHash(_ personID: String) -> String {
        let key = SymmetricKey(data: Data(linkSalt.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(personID.lowercased().utf8), using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    /// The same for everyone in the group: a hash of the sorted person ids.
    static func groupKey(_ personIDs: [String]) -> String {
        let joined = personIDs.map { $0.lowercased() }.sorted().joined(separator: ",")
        return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    /// What each partner told us (by bond code): their person id and their links.
    struct Known: Codable, Equatable {
        var personID: String?
        var links: [String]?
    }
    private static let knownKey = "stand.known"
    static func known() -> [String: Known] {
        UserDefaults.standard.data(forKey: knownKey).flatMap { try? JSONDecoder().decode([String: Known].self, from: $0) } ?? [:]
    }
    static func saveKnown(_ map: [String: Known]) {
        if let data = try? JSONEncoder().encode(map) { UserDefaults.standard.set(data, forKey: knownKey) }
    }
}

/// Three or more people all bonded with each other.
struct StandGroup: Identifiable, Equatable {
    let key: String
    /// The other members' person ids and their bond codes with me.
    let members: [String]
    let bondIDs: [String]
    var id: String { key }
}

/// Where a part of Where we stand reads and writes: one pair space, or every pair space with
/// a group's members. `me` is "A"/"B" in a pair, my person id in a group.
struct StandScope: Equatable {
    var bondIDs: [String]
    var groupKey: String?
    var me: String
    var isGroup: Bool { groupKey != nil }
    var bondID: String? { bondIDs.first }
}

/// A Where-we-stand item that can belong to a group.
protocol StandGrouped: SyncItem {
    var groupKey: String? { get }
}
extension StandWish: StandGrouped {}
extension StandPromise: StandGrouped {}
extension StandMark: StandGrouped {}
