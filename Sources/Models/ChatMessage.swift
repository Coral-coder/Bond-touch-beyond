import Foundation

/// A chat message in a bond (text, or a touch rendered inline). Relayed over CloudKit.
struct ChatMessage: Identifiable, Equatable {
    enum Kind: String { case text, touch }

    let id: UUID
    let bondID: String
    let senderID: String
    let kind: Kind
    let text: String
    let colorRGB: Int
    let sentAt: Date

    init(id: UUID = UUID(), bondID: String, senderID: String, kind: Kind = .text,
         text: String = "", colorRGB: Int = 0xFF4081, sentAt: Date = Date()) {
        self.id = id
        self.bondID = bondID
        self.senderID = senderID
        self.kind = kind
        self.text = text
        self.colorRGB = colorRGB
        self.sentAt = sentAt
    }
}
