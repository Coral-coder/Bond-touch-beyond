import CryptoKit
import Foundation
import Security
import UIKit
import WidgetKit

/// What the app and its widgets share: a small snapshot the app writes — the selected
/// partner and their first meanings, the last touch received, your days together and the next
/// special date — plus the result of each widget send. The widgets only read, except for
/// queueing a send when they have to (see `SendMeaningIntent`).
///
/// Shared through the app's Keychain group (`BTKeychainGroup`), not an App Group, so it needs
/// no developer-portal setup. Items: `snapshot.json`, `status.json`, `requests.json`.
enum WidgetShared {
    static let kind = "BondTouchBeyondWidget"
    static let lastTouchKind = "BondTouchBeyondLastTouch"
    static let togetherKind = "BondTouchBeyondTogether"
    static let moodKind = "BondTouchBeyondMood"
    /// The original's widget has up to 10 meaning slots.
    static let maxMeanings = 10
    /// How long Sent / Failed shows on a meaning.
    static let resultSeconds: TimeInterval = 5
    /// A queued send older than this is dropped (and shown failed) rather than sent late.
    static let requestLifetime: TimeInterval = 10 * 60

    /// Darwin notification the widget posts after queueing a send.
    static let requestNotification = "com.lightwave.beyond.widget-send"

    /// Always available (the Keychain group needs no setup).
    static var available: Bool { true }

    private static let snapshotFile = "snapshot.json"
    private static let statusFile = "status.json"
    private static let requestsFile = "requests.json"

    // MARK: - Storage (Keychain)

    private static let service = "BondTouchBeyond.widget"
    private static var group: String? {
        (Bundle.main.object(forInfoDictionaryKey: "BTKeychainGroup") as? String).flatMap { $0.isEmpty || $0.contains("$(") ? nil : $0 }
    }

    private static func query(_ name: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: name]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    static func data(_ name: String) -> Data? {
        var q = query(name)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func write(_ data: Data, named name: String) {
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(query(name) as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query(name).merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    static func remove(_ name: String) { SecItemDelete(query(name) as CFDictionary) }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = data(name) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        write(data, named: name)
    }

    static func image(_ data: Data?) -> UIImage? { data.flatMap(UIImage.init(data:)) }

    /// A short stable key (Swift's own hashes change every launch).
    static func fileKey(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    static func reloadWidget() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Snapshot

    static func loadSnapshot() -> WidgetSnapshot? { read(WidgetSnapshot.self, snapshotFile) }

    /// Saves the snapshot; false (and nothing written) when it hasn't changed.
    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard loadSnapshot() != snapshot else { return false }
        write(snapshot, snapshotFile)
        return true
    }

    // MARK: - Send status

    /// The latest send state per meaning (by `WidgetSnapshot.Meaning.id`), dropping old ones.
    static func statuses(now: Date = Date()) -> [String: WidgetSendStatus] {
        (read([String: WidgetSendStatus].self, statusFile) ?? [:]).filter { $0.value.visibleUntil > now }
    }

    static func setStatus(_ state: WidgetSendState, for meaningID: String) {
        var all = statuses()
        all[meaningID] = WidgetSendStatus(state: state, at: Date())
        write(all, statusFile)
    }

    // MARK: - Queued sends (widget → app)

    static func enqueue(_ request: WidgetSendRequest) {
        var queue = read([WidgetSendRequest].self, requestsFile) ?? []
        queue.append(request)
        write(queue, requestsFile)
        setStatus(.queued, for: request.meaningID)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(requestNotification as CFString), nil, nil, true)
    }

    /// Reads and clears the queue.
    static func takeRequests() -> [WidgetSendRequest] {
        guard let queue = read([WidgetSendRequest].self, requestsFile), !queue.isEmpty else { return [] }
        remove(requestsFile)
        return queue
    }

    // MARK: - Deep link (iOS 16: a tap opens the app, which sends)

    /// `bondtouchbeyond://send?meaning=<id>&bond=<bond id>`.
    static func sendURL(meaningID: String, bondID: String) -> URL {
        var c = URLComponents()
        c.scheme = "bondtouchbeyond"
        c.host = "send"
        c.queryItems = [URLQueryItem(name: "meaning", value: meaningID), URLQueryItem(name: "bond", value: bondID)]
        return c.url ?? URL(string: "bondtouchbeyond://send")!
    }

    static func sendRequest(from url: URL) -> WidgetSendRequest? {
        guard url.scheme == "bondtouchbeyond", url.host == "send",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let meaning = items.first(where: { $0.name == "meaning" })?.value, !meaning.isEmpty,
              let bond = items.first(where: { $0.name == "bond" })?.value, !bond.isEmpty else { return nil }
        return WidgetSendRequest(meaningID: meaning, bondID: bond, at: Date())
    }
}

/// The widget's view of the app: the selected partner and their first meanings
/// (favourites first).
struct WidgetSnapshot: Codable, Equatable {
    struct Partner: Codable, Equatable {
        var id: String          // bond id
        var name: String
        var colorRGB: Int
        /// A small JPEG of their photo, if they have one.
        var photo: Data?
    }

    /// The last touch received from the partner.
    struct LastTouch: Codable, Equatable {
        var from: String
        var pattern: [Int]
        var generation: Int
        var colorRGB: Int
        var endColorRGB: Int
        var label: String?
        var emoji: String?
        var bpm: Int?
        var at: Date
    }

    /// Your days together and the next special date.
    struct Together: Codable, Equatable {
        var since: Date?
        var nextTitle: String?
        var nextDate: Date?
        var nextIsBirthday: Bool = false
    }

    struct Meaning: Codable, Equatable, Identifiable {
        /// The original backend's meaning id for an original-app partner (stable across
        /// syncs), else the local meaning's UUID.
        var id: String
        var label: String
        var emoji: String
        var colorRGB: Int
        var endColorRGB: Int
        /// Raw touch, so the app can still send it if the meaning is not loaded yet, and so
        /// the widget can draw it if the rendered image is missing.
        var pattern: [Int]
        var generation: Int
        var serverID: String?
        var favourite: Bool
        /// Not used any more (the widget draws the touch itself).
        var imageFile: String? = nil
    }

    /// How the partner's feeling (what they share in Stress & mood).
    struct Mood: Codable, Equatable {
        var emoji: String
        var label: String
        /// 0–100: their energy (personal battery).
        var energy: Int
        /// 0–100.
        var stress: Int
        var at: Date
    }

    var partner: Partner?
    var meanings: [Meaning]
    var mood: Mood? = nil
    var lastTouch: LastTouch? = nil
    var together: Together? = nil
    /// The weather where the partner is.
    var weather: WeatherInfo? = nil
    /// Settings → Units ("auto", "imperial" or "metric").
    var units: String? = nil
}

enum WidgetSendState: String, Codable {
    /// The app is sending it.
    case sending
    /// The widget queued it for the app (it couldn't run the send itself).
    case queued
    case sent
    case failed
}

struct WidgetSendStatus: Codable, Equatable {
    var state: WidgetSendState
    var at: Date

    /// Sent / Failed show for a few seconds; Sending / Queued until the result replaces
    /// them, or 30 s if the app never reports back.
    var visibleUntil: Date {
        switch state {
        case .sent, .failed: return at.addingTimeInterval(WidgetShared.resultSeconds)
        case .sending, .queued: return at.addingTimeInterval(30)
        }
    }
}

struct WidgetSendRequest: Codable, Equatable {
    var meaningID: String
    var bondID: String
    var at: Date
}
