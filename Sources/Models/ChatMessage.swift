import Foundation

/// A chat message in a bond: text, a photo, or a touch rendered inline. Relayed over
/// CloudKit.
struct ChatMessage: Identifiable, Equatable, Codable {
    enum Kind: String, Codable { case text, touch, image }

    /// A fixed `senderID` for the user's own messages and touches where no CloudKit user id
    /// applies (the demo, and history saved by older versions). Treated as "mine".
    static let localSelf = "me"

    let id: UUID
    let bondID: String
    let senderID: String
    let kind: Kind
    let text: String
    let colorRGB: Int
    let sentAt: Date
    /// Unused: a message id from the original Bond Touch servers, kept so history saved by
    /// older versions still decodes.
    var serverID: String? = nil
    /// File name of a photo saved in the app's chat-media folder.
    var imageFile: String? = nil
    /// For our own iCloud messages: its number in this phone's message ring (read receipts).
    var ringSeq: Int? = nil

    init(id: UUID = UUID(), bondID: String, senderID: String, kind: Kind = .text,
         text: String = "", colorRGB: Int = 0xFF4081, sentAt: Date = Date(),
         serverID: String? = nil, imageFile: String? = nil) {
        self.id = id
        self.bondID = bondID
        self.senderID = senderID
        self.kind = kind
        self.text = text
        self.colorRGB = colorRGB
        self.sentAt = sentAt
        self.serverID = serverID
        self.imageFile = imageFile
    }
}

/// On-device chat history, plus the photos. Stored in Application Support with complete
/// file protection.
enum ChatArchive {
    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static var mediaDir: URL {
        let d = dir.appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // The file name dates from older versions; kept so existing history still loads.
    private static var file: URL { dir.appendingPathComponent("legacy-chat.json") }

    static func load() -> [String: [ChatMessage]] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        var messages = (try? JSONDecoder().decode([String: [ChatMessage]].self, from: data)) ?? [:]
        if expire(&messages) { save(messages) }
        return messages
    }

    /// How long Private Space keeps messages and photos, as the original app (72 hours).
    static let lifetime: TimeInterval = 72 * 3600

    /// Drops messages older than `lifetime` — and deletes their photos from the phone.
    /// Returns true when anything was removed.
    @discardableResult
    static func expire(_ messages: inout [String: [ChatMessage]], now: Date = Date()) -> Bool {
        var removed = false
        for (bond, list) in messages {
            let (keep, drop) = list.reduce(into: ([ChatMessage](), [ChatMessage]())) { acc, m in
                if now.timeIntervalSince(m.sentAt) < lifetime { acc.0.append(m) } else { acc.1.append(m) }
            }
            guard !drop.isEmpty else { continue }
            for m in drop { if let f = m.imageFile { try? FileManager.default.removeItem(at: imageURL(f)) } }
            messages[bond] = keep
            removed = true
        }
        return removed
    }

    static func save(_ messages: [String: [ChatMessage]]) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtection])
    }

    static func saveImage(_ data: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: mediaDir.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            return name
        } catch { return nil }
    }

    static func imageURL(_ name: String) -> URL { mediaDir.appendingPathComponent(name) }

    static func wipe() { try? FileManager.default.removeItem(at: dir) }
}
