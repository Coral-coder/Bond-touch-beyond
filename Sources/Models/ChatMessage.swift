import Foundation

/// A chat message in a bond: text, a photo, or a touch rendered inline. Relayed over
/// CloudKit, or end-to-end encrypted through the original Bond backend for original-app
/// partners.
struct ChatMessage: Identifiable, Equatable, Codable {
    enum Kind: String, Codable { case text, touch, image }

    /// `senderID` of the user's own messages on the original backend (the CloudKit user
    /// id may be unknown or change, so those messages use this fixed marker).
    static let legacySelf = "me"

    let id: UUID
    let bondID: String
    let senderID: String
    let kind: Kind
    let text: String
    let colorRGB: Int
    let sentAt: Date
    /// The message id on the original backend (dedup, delivery acks, deletion).
    var serverID: String? = nil
    /// File name of a photo saved in the app's chat-media folder.
    var imageFile: String? = nil

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

/// On-device history of chat with original-app partners (the server only holds messages
/// until they are acknowledged), plus the decrypted photos. Stored in Application Support
/// with complete file protection.
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

    private static var file: URL { dir.appendingPathComponent("legacy-chat.json") }

    static func load() -> [String: [ChatMessage]] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: [ChatMessage]].self, from: data)) ?? [:]
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
