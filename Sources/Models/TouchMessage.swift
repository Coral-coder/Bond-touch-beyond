import Foundation

/// A single "touch" exchanged between partners.
///
/// `pattern` is in the format of `generation` (see `TouchPattern`): generation 2 is an
/// on/off millisecond list; generation 3 (Bond Touch More, the on-screen and watch touch
/// bars) is one 50 ms position sample per entry — a 2D trace of time × finger position.
struct TouchMessage: Identifiable, Codable, Equatable {
    let id: UUID
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

    init(id: UUID = UUID(), senderID: String, pattern: [Int], generation: Int = 2,
         colorRGB: Int, endColorRGB: Int? = nil, sentAt: Date = Date()) {
        self.id = id
        self.senderID = senderID
        self.pattern = pattern
        self.generation = generation == 3 ? 3 : 2
        self.colorRGB = colorRGB
        self.endColorRGB = endColorRGB ?? colorRGB
        self.sentAt = sentAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, senderID, pattern, generation, colorRGB, endColorRGB, sentAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        senderID = try c.decode(String.self, forKey: .senderID)
        pattern = try c.decode([Int].self, forKey: .pattern)
        generation = try c.decodeIfPresent(Int.self, forKey: .generation) ?? 2
        colorRGB = try c.decode(Int.self, forKey: .colorRGB)
        endColorRGB = try c.decodeIfPresent(Int.self, forKey: .endColorRGB) ?? colorRGB
        sentAt = try c.decode(Date.self, forKey: .sentAt)
    }

    /// The pattern as on/off milliseconds (for generation-2 bracelets).
    var onOffMs: [Int] { generation == 3 ? TouchPattern.onOff(fromSamples: pattern) : pattern }

    /// The pattern as 50 ms position samples (for the Bond Touch More).
    var samples: [Int] { generation == 3 ? pattern : TouchPattern.samples(fromOnOff: pattern) }
}
