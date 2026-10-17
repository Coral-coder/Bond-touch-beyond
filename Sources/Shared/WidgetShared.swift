import CryptoKit
import Foundation
import UIKit
import WidgetKit

/// What the app and its home-screen widget share, through the App Group container (compiled
/// into both targets). The app writes a small snapshot — the selected partner and their first
/// meanings, with a photo thumbnail and a rendered image of each touch — and the result of
/// each widget send; the widget only reads, except for queueing a send when it has to (see
/// `SendMeaningIntent`).
///
/// Files, in `<group>/Widget/`: `snapshot.json`, `status.json` (Sent / Failed per meaning),
/// `requests.json` (sends queued by the widget for the app), and the images.
enum WidgetShared {
    static let kind = "BondTouchBeyondWidget"
    /// The original's widget has up to 10 meaning slots.
    static let maxMeanings = 10
    /// How long Sent / Failed shows on a meaning.
    static let resultSeconds: TimeInterval = 5
    /// A queued send older than this is dropped (and shown failed) rather than sent late.
    static let requestLifetime: TimeInterval = 10 * 60

    /// `group.<app bundle id>`, from the `BTAppGroup` Info.plist key both targets carry (the
    /// bundle id can be overridden at build time, so it isn't hardcoded).
    static let appGroupID: String = {
        if let id = Bundle.main.object(forInfoDictionaryKey: "BTAppGroup") as? String,
           !id.isEmpty, !id.contains("$(") { return id }
        return "group." + AppGroupFallback.bundleID
    }()

    /// Darwin notification the widget posts after queueing a send.
    static var requestNotification: String { appGroupID + ".widget-send" }

    /// The shared folder, or nil when the App Group isn't available (an unsigned build).
    static var directory: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let dir = base.appendingPathComponent("Widget", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let snapshotFile = "snapshot.json"
    private static let statusFile = "status.json"
    private static let requestsFile = "requests.json"
    static let dataFiles: Set<String> = [snapshotFile, statusFile, requestsFile]

    // MARK: - Files

    static func url(_ name: String) -> URL? { directory?.appendingPathComponent(name) }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let url = url(name), let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func write(_ data: Data, named name: String) {
        guard let url = url(name) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func fileExists(_ name: String) -> Bool {
        guard let url = url(name) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func image(named name: String?) -> UIImage? {
        guard let name, let url = url(name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Deletes images no longer named by the snapshot.
    static func removeFiles(except keep: Set<String>) {
        guard let dir = directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where !dataFiles.contains(name) && !keep.contains(name) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// A short stable file-name key (Swift's own hashes change every launch).
    static func fileKey(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    static func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
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
        if let url = url(requestsFile) { try? FileManager.default.removeItem(at: url) }
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

/// Only used if the Info.plist key is missing.
private enum AppGroupFallback {
    static var bundleID: String {
        let id = Bundle.main.bundleIdentifier ?? "com.lightwave.beyond"
        return id.hasSuffix(".widget") ? String(id.dropLast(".widget".count)) : id
    }
}

/// The widget's view of the app: the selected partner and their first meanings
/// (favourites first).
struct WidgetSnapshot: Codable, Equatable {
    struct Partner: Codable, Equatable {
        var id: String          // bond id
        var name: String
        var colorRGB: Int
        /// Small JPEG in the shared folder, if the partner has a photo.
        var photoFile: String?
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
        /// PNG of the touch (TouchViz) in the shared folder.
        var imageFile: String?
    }

    var partner: Partner?
    var meanings: [Meaning]
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
