import Foundation

/// A single "touch" exchanged between paired bracelets.
///
/// Bond Touch's interaction is: you tap your bracelet N times, and your partner's
/// bracelet plays back that same rhythm (and a chosen colour). We model a touch as
/// the rhythm (inter-tap gaps) plus a colour, which is everything the peer needs to
/// reproduce it on their own hardware.
struct TouchMessage: Identifiable, Codable, Equatable {
    let id: UUID
    /// Who sent it (CloudKit user record name of the sender).
    let senderID: String
    /// Milliseconds between consecutive taps; `pattern.count + 1` taps total.
    /// An empty array is a single tap.
    let pattern: [Int]
    /// 0xRRGGBB colour the partner's bracelet should glow.
    let colorRGB: Int
    /// When the sender created it.
    let sentAt: Date

    init(id: UUID = UUID(), senderID: String, pattern: [Int], colorRGB: Int, sentAt: Date = Date()) {
        self.id = id
        self.senderID = senderID
        self.pattern = pattern
        self.colorRGB = colorRGB
        self.sentAt = sentAt
    }
}
