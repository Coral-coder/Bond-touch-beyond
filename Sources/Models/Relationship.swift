import Foundation

// The relationship tools in the Us space: love-language check-ins, the appreciation jar,
// date roulette, a question of the day, the poly calendar, agreements, metamours and
// compersion, repair, memory lane and the co-op games. Each is a list of `SyncItem`s in
// `TogetherSpace`, so both phones merge them item by item like the to-dos.

// MARK: Love languages

enum LoveLanguage: String, Codable, CaseIterable, Identifiable {
    case words, time, touch, acts, gifts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .words: return "Words of affirmation"
        case .time: return "Quality time"
        case .touch: return "Physical touch"
        case .acts: return "Acts of service"
        case .gifts: return "Gifts"
        }
    }
    var emoji: String {
        switch self { case .words: return "💬"; case .time: return "⏳"; case .touch: return "🤗"; case .acts: return "🧺"; case .gifts: return "🎁" }
    }
}

/// How full one of you feels in each love language this week (0–5), and what you'd love more of.
struct LoveCheck: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var by: String
    /// love-language raw value → 0…5.
    var levels: [String: Int] = [:]
    var wish = ""
}

// MARK: Appreciation jar

/// A little note of appreciation for the other one, kept folded in the jar until they open it.
struct Appreciation: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var by: String
    var text: String
    var opened = false
}

// MARK: Date roulette

struct DateIdea: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var text: String
    var emoji: String = "✨"
    /// 0 free, 1 cheap, 2 a treat.
    var cost = 0
    var athome = false
    var done = false
    var doneAt: Date?
    var by: String = ""

    static let starters: [(String, String, Int, Bool)] = [
        ("Cook a new recipe together", "🍝", 1, true), ("Picnic in the park", "🧺", 1, false),
        ("Stargazing with blankets", "🌌", 0, false), ("Build a blanket fort and watch a film", "🏰", 0, true),
        ("Go to a museum you've never been to", "🖼️", 1, false), ("Sunrise walk with coffee", "🌅", 0, false),
        ("Board game night", "🎲", 0, true), ("Take a dance class", "💃", 2, false),
        ("Write each other letters, read them aloud", "💌", 0, true), ("Try a restaurant neither of you has been to", "🍜", 2, false),
        ("Paint each other's portrait", "🎨", 1, true), ("Karaoke night", "🎤", 1, false),
        ("A day trip somewhere new", "🚗", 2, false), ("Spa night at home", "🛁", 1, true),
        ("Thrift-store challenge: dress each other for $10", "🧥", 1, false), ("Bake something ridiculous", "🧁", 1, true),
        ("Go for a bike ride", "🚲", 0, false), ("Do a puzzle with a playlist on", "🧩", 0, true),
        ("Visit a farmers' market", "🥕", 1, false), ("Recreate your first date", "💞", 1, false),
    ]
}

// MARK: Question of the day

/// One answer to a day's question. Both phones show the same question each day.
struct QuestionAnswer: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    /// "2026-10-19"
    var day: String
    var by: String
    var text: String
}

enum DailyQuestion {
    static let all: [String] = [
        "What's a small thing I did recently that made you smile?",
        "Where would you go if we could leave tomorrow for a week?",
        "What's a memory of us you replay in your head?",
        "What's something you've never told me about your childhood?",
        "What do you need more of from me right now?",
        "What's a song that makes you think of us?",
        "What's one thing you'd like us to try this year?",
        "When did you first know you liked me?",
        "What's your favourite way to spend a lazy Sunday with me?",
        "What's something you're proud of this week?",
        "What's a fear you'd like help with?",
        "What does a perfect evening together look like?",
        "Which of my habits secretly charms you?",
        "What's a dream you haven't said out loud yet?",
        "How do you like to be comforted when you're sad?",
        "What's the best gift you've ever received?",
        "What's a tradition you'd like us to start?",
        "If we had a theme song, what would it be?",
        "What's something new you learned about yourself lately?",
        "What made you laugh the hardest this month?",
        "What's one way I could make your mornings better?",
        "What's a place that feels like home to you?",
        "Which fictional couple are we most like?",
        "What do you love about how we argue — or wish we did differently?",
        "What's a skill you'd like us to learn together?",
        "What's your earliest happy memory?",
        "What's something that always calms you down?",
        "What would you want our home to feel like in five years?",
        "What's a compliment you'd love to hear more often?",
        "What are you looking forward to most right now?",
        "What's a small adventure we could have this weekend?",
        "What did you love most about today?",
        "What's a food that reminds you of someone you love?",
        "How can I support you better when you're stressed?",
        "What's the kindest thing a stranger has done for you?",
        "If we wrote a book about us, what would chapter one be called?",
        "What's a boundary you'd like me to know about?",
        "What's a moment you felt really seen by me?",
        "What's a hobby of mine you'd like to try?",
        "What does feeling safe with someone mean to you?",
    ]

    static func key(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Same on both phones: picked from the date.
    static func question(for date: Date = Date()) -> String {
        let days = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970 / 86_400)
        return all[((days * 7) % all.count + all.count) % all.count]
    }

    static func question(forKey key: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key).map { question(for: $0) } ?? all[0]
    }
}

// MARK: Poly calendar

/// Time planned with someone: a date night, a weekend away, a night at a metamour's.
/// Each partner's calendar lives in your space with them; the poly calendar shows all of them.
struct CalendarEvent: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var by: String
    var title: String
    var start: Date
    var end: Date
    /// Who it's with, in words ("Us", "Jamie", "Family") — free text, never a contact.
    var with = "Us"
    var emoji = "💞"
}

// MARK: Agreements

/// Something you both agree to. Changing the wording asks you both to agree again.
struct Agreement: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var text: String
    var topic = "General"
    var agreedA: Date?
    var agreedB: Date?
    /// Look at it again on or after this date.
    var review: Date?
    var by: String

    var bothAgreed: Bool { agreedA != nil && agreedB != nil }
    func agreed(_ role: String) -> Bool { role == "A" ? agreedA != nil : agreedB != nil }

    static let topics = ["General", "Communication", "Time", "Safer sex", "Dating others", "Home", "Money", "Privacy"]
}

// MARK: Metamours and compersion

/// One of your partner's other partners, as your partner describes them for you.
struct Metamour: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    /// Whose partner they are ("A" or "B").
    var of: String
    var name: String
    var emoji = "🌷"
    var notes = ""
    var birthday: Date?
}

/// A moment of compersion: joy for your partner's joy.
struct CompersionNote: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var by: String
    var text: String
}

// MARK: Repair

/// After a hard moment: a time-out, a feelings note in "I feel … when … I need …" form, or a
/// repair attempt. Time-outs show the other one when you'll be back.
struct RepairNote: SyncItem, Equatable {
    enum Kind: String, Codable { case timeout, feeling, repair, resolved }
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var by: String
    var kind: Kind
    var text = ""
    /// For a time-out: when you'll come back.
    var until: Date?

    static let repairs = [
        "I'm sorry, I got that wrong.", "Can we start over?", "I love you, even now.",
        "Let me try again, more gently.", "I can see why you feel that way.", "Can I have a hug?",
        "This matters to me because you matter to me.", "I need a minute, but I'm coming back.",
        "What do you need from me right now?", "We're on the same team.",
    ]
}

// MARK: Memory lane

struct Memory: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var by: String
    var title: String
    var date: Date
    var emoji = "📸"
    var text = ""
}

// MARK: Co-op games

/// One line of the story you write together, a sentence each in turn.
struct StoryLine: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var by: String
    var text: String
    /// Which story (a new one starts with a new id).
    var story: UUID
}

/// Same Wavelength: both pick an answer to a this-or-that without seeing the other's; you
/// score together for every match.
struct WavelengthPick: SyncItem, Equatable {
    var id = UUID()
    var created = Date()
    var edited = Date()
    var deleted = false
    var by: String
    /// Question number.
    var q: Int
    /// 0 or 1.
    var pick: Int
}

enum Wavelength {
    static let questions: [(String, String)] = [
        ("Beach", "Mountains"), ("Sunrise", "Sunset"), ("Cats", "Dogs"), ("Sweet", "Savoury"),
        ("Night in", "Night out"), ("Coffee", "Tea"), ("Plan everything", "Wing it"), ("Books", "Films"),
        ("Summer", "Winter"), ("City break", "Cabin in the woods"), ("Pizza", "Tacos"), ("Text", "Call"),
        ("Early bird", "Night owl"), ("Road trip", "Fly there"), ("Board games", "Video games"),
        ("Breakfast in bed", "Brunch out"), ("Rain on the window", "Sun on the skin"), ("Big party", "Small dinner"),
        ("Spicy", "Mild"), ("Museum", "Theme park"), ("Bath", "Shower"), ("Chocolate", "Ice cream"),
        ("Matching outfits", "Never"), ("Slow dance", "Jump around"), ("Handwritten letter", "Surprise playlist"),
        ("Camping", "Hotel"), ("Pancakes", "Waffles"), ("Ocean", "Lake"), ("Comedy", "Horror"), ("Stay up late", "Sleep in"),
    ]
}

// MARK: Helpers for the optional lists

func syncLive<T: SyncItem>(_ list: [T]?) -> [T] { (list ?? []).filter { !$0.deleted } }

func syncAppend<T: SyncItem>(_ list: inout [T]?, _ item: T) { list = (list ?? []) + [item] }

func syncUpdate<T: SyncItem>(_ list: inout [T]?, _ id: UUID, _ change: (inout T) -> Void) {
    guard var l = list, let i = l.firstIndex(where: { $0.id == id }) else { return }
    change(&l[i])
    l[i].edited = Date()
    list = l
}

func syncDelete<T: SyncItem>(_ list: inout [T]?, _ id: UUID) { syncUpdate(&list, id) { $0.deleted = true } }
