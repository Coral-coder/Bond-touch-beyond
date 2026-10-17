import CryptoKit
import Foundation

/// A single "touch" exchanged between partners.
///
/// `pattern` is in the format of `generation` (see `TouchPattern`): generation 2 is an
/// on/off millisecond list; generation 3 (Bond Touch More, the on-screen and watch touch
/// bars) is one 50 ms position sample per entry — a 2D trace of time × finger position.
struct TouchMessage: Identifiable, Codable, Equatable {
    let id: UUID
    /// Which bond (partner) this touch belongs to, so history is shown per partner.
    var bondID: String = ""
    /// Who sent it (CloudKit user record name, the partner's Firebase id, or "me").
    let senderID: String
    let pattern: [Int]
    /// 2 = on/off milliseconds, 3 = 50 ms position samples.
    let generation: Int
    /// 0xRRGGBB start colour of the touch's gradient.
    let colorRGB: Int
    /// 0xRRGGBB end colour of the gradient. Equals `colorRGB` for a single-colour touch.
    let endColorRGB: Int
    /// When the sender created it.
    let sentAt: Date
    /// The saved meaning this touch is ("Love you"), when it was sent as one or closely
    /// matches one — shown over the touch on Home.
    var meaningLabel: String?
    var meaningEmoji: String?

    init(id: UUID = UUID(), bondID: String = "", senderID: String, pattern: [Int], generation: Int = 2,
         colorRGB: Int, endColorRGB: Int? = nil, sentAt: Date = Date(),
         meaningLabel: String? = nil, meaningEmoji: String? = nil) {
        self.id = id
        self.bondID = bondID
        self.senderID = senderID
        self.pattern = pattern
        self.generation = generation == 3 ? 3 : 2
        self.colorRGB = colorRGB
        self.endColorRGB = endColorRGB ?? colorRGB
        self.sentAt = sentAt
        self.meaningLabel = meaningLabel
        self.meaningEmoji = meaningEmoji
    }

    private enum CodingKeys: String, CodingKey {
        case id, bondID, senderID, pattern, generation, colorRGB, endColorRGB, sentAt, meaningLabel, meaningEmoji
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bondID = try c.decodeIfPresent(String.self, forKey: .bondID) ?? ""
        senderID = try c.decode(String.self, forKey: .senderID)
        pattern = try c.decode([Int].self, forKey: .pattern)
        generation = try c.decodeIfPresent(Int.self, forKey: .generation) ?? 2
        colorRGB = try c.decode(Int.self, forKey: .colorRGB)
        endColorRGB = try c.decodeIfPresent(Int.self, forKey: .endColorRGB) ?? colorRGB
        sentAt = try c.decode(Date.self, forKey: .sentAt)
        meaningLabel = try c.decodeIfPresent(String.self, forKey: .meaningLabel)
        meaningEmoji = try c.decodeIfPresent(String.self, forKey: .meaningEmoji)
    }

    /// The pattern as on/off milliseconds (for generation-2 bracelets).
    var onOffMs: [Int] { generation == 3 ? TouchPattern.onOff(fromSamples: pattern) : pattern }

    /// The pattern as 50 ms position samples (for the Bond Touch More).
    var samples: [Int] { generation == 3 ? pattern : TouchPattern.samples(fromOnOff: pattern) }

    /// A stable id derived from a server touch id, so the same touch gets the same id across
    /// launches and isn't duplicated in the saved feed when it's re-fetched.
    static func stableID(from serverTouchID: String) -> UUID {
        if let u = UUID(uuidString: serverTouchID) { return u }
        let digest = Array(SHA256.hash(data: Data(serverTouchID.utf8)).prefix(16))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5],
                           digest[6], digest[7], digest[8], digest[9], digest[10], digest[11],
                           digest[12], digest[13], digest[14], digest[15]))
    }
}

/// Saves recent touches to disk so the feed survives closing the app and updating. Keeps
/// the most recent `perBond` touches for each partner (the backends re-add newer ones).
enum TouchArchive {
    static let perBond = 40

    private static var file: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("touches.json")
    }

    static func load() -> [TouchMessage] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([TouchMessage].self, from: data)) ?? []
    }

    /// Caps to the most recent `perBond` per partner, oldest-first overall, and saves.
    static func save(_ history: [TouchMessage]) {
        var byBond: [String: [TouchMessage]] = [:]
        for t in history { byBond[t.bondID, default: []].append(t) }
        var capped: [TouchMessage] = []
        for list in byBond.values { capped.append(contentsOf: list.suffix(perBond)) }
        capped.sort { $0.sentAt < $1.sentAt }
        if let data = try? JSONEncoder().encode(capped) {
            try? data.write(to: file, options: [.atomic, .completeFileProtection])
        }
    }
}
