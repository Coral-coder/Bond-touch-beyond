import Foundation
import UserNotifications

/// Where a tapped notification takes you.
enum AppRoute: Equatable {
    /// Home, with the touch (or heartbeat, kiss, arrival) that came in.
    case home
    /// The chat (Private Space).
    case chat
    /// A part of Us, by its tile id ("todos", "games", "stress", …), plus "dates" and "likes";
    /// nil is the Us screen itself.
    case us(String?)
    /// Settings → My Bond Touch Bracelet.
    case bracelet
}

extension AppModel {
    /// A notification was tapped: select the partner it's from and open the part of the app it
    /// is about. Works for partners' pushes (old builds too, from the notification's id) and
    /// for this phone's own reminders.
    func openNotification(id: String, userInfo info: [AnyHashable: Any]) {
        let bondID = info[TouchNotification.Key.bond] as? String
            ?? (info["bl"] as? String).flatMap { locator in partners.first { BondCrypto.locator(forCode: $0.id) == locator }?.id }
        if let bondID, partners.contains(where: { $0.id == bondID }) { selectedPartnerID = bondID }
        // The kind: carried in the push ("g"), or the start of the id ("t-…", "u.todos-…",
        // "date-…", "bracelet-battery").
        let kind = info["g"] as? String ?? String(id.split(separator: "-", maxSplits: 1).first ?? "")
        route = Self.route(forKind: kind, id: id)
    }

    static func route(forKind kind: String, id: String) -> AppRoute {
        switch kind {
        case "m": return .chat
        case "c": return .us("stress")
        case "bracelet": return .bracelet
        case "date": return id.hasPrefix("date-radar-") ? .us("radar") : .us("dates")
        case "t", "h", "a", "k", "l": return .home
        default:
            guard kind.hasPrefix("u.") else { return .home }
            switch String(kind.dropFirst(2)) {
            case "todos": return .us("todos")
            case "notes": return .us("notes")
            case "whiteboard": return .us("whiteboard")
            case "dates": return .us("dates")
            case "likes": return .us("likes")
            case "language": return .us("language")
            case "games": return .us("games")
            case "love": return .us("love")
            case "jar": return .us("jar")
            case "roulette": return .us("roulette")
            case "question": return .us("question")
            case "agreements": return .us("agreements")
            case "repair": return .us("repair")
            case "memories": return .us("memories")
            case "radar": return .us("radar")
            case "calendar": return .us("polycal")
            case "metamours": return .us("metamours")
            default: return .us(nil)
            }
        }
    }
}
