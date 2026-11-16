import Foundation
import UIKit

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
    /// For our own iCloud messages: its number in this phone's message ring (read receipts).
    var ringSeq: Int? = nil
    /// A photo's view timer, chosen by the sender: seconds it can be looked at once opened
    /// (nil or 0: no limit).
    var viewSeconds: Int? = nil
    /// When a timed photo was first opened on this phone (its timer runs from then).
    var openedAt: Date? = nil
    /// A timed photo whose time is up: its file has been deleted from this phone.
    var expired: Bool? = nil

    init(id: UUID = UUID(), bondID: String, senderID: String, kind: Kind = .text,
         text: String = "", colorRGB: Int = 0xFF4081, sentAt: Date = Date(),
         serverID: String? = nil, imageFile: String? = nil, viewSeconds: Int? = nil) {
        self.id = id
        self.bondID = bondID
        self.senderID = senderID
        self.kind = kind
        self.text = text
        self.colorRGB = colorRGB
        self.sentAt = sentAt
        self.serverID = serverID
        self.imageFile = imageFile
        self.viewSeconds = viewSeconds
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
        var d = dir.appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        // Photos never go into an iCloud or computer backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? d.setResourceValues(values)
        return d
    }

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

    /// Saves a photo sealed with this device's key (see `ChatVault`), under file protection.
    static func saveImage(_ data: Data) -> String? {
        guard let sealed = ChatVault.seal(data) else { return nil }
        let name = UUID().uuidString + ".enc"
        do {
            try sealed.write(to: mediaDir.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            return name
        } catch { return nil }
    }

    /// A saved photo's bytes, unsealed. Photos saved before they were sealed (".jpg") are read as they are.
    static func imageData(_ name: String) -> Data? {
        guard let data = try? Data(contentsOf: imageURL(name)) else { return nil }
        return name.hasSuffix(".enc") ? ChatVault.open(data) : data
    }

    static func image(_ name: String) -> UIImage? { imageData(name).flatMap(UIImage.init(data:)) }

    static func deleteImage(_ name: String) { try? FileManager.default.removeItem(at: imageURL(name)) }

    static func imageURL(_ name: String) -> URL { mediaDir.appendingPathComponent(name) }

    static func wipe() { try? FileManager.default.removeItem(at: dir) }
}
