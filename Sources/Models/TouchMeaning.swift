import Foundation

/// A saved "meaning" for a touch — the original app lets partners agree that a given
/// rhythm/colour means something ("thinking of you", "goodnight"). Sending a meaning
/// sends its pattern + colour.
struct TouchMeaning: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var emoji: String
    var colorRGB: Int
    var pattern: [Int]   // inter-tap gaps in ms

    static let starters: [TouchMeaning] = [
        TouchMeaning(label: "Thinking of you", emoji: "💭", colorRGB: 0xFF4081, pattern: [200, 200]),
        TouchMeaning(label: "Goodnight", emoji: "🌙", colorRGB: 0x3F51B5, pattern: [500]),
        TouchMeaning(label: "I love you", emoji: "❤️", colorRGB: 0xF44336, pattern: [150, 150, 150]),
        TouchMeaning(label: "Miss you", emoji: "🥺", colorRGB: 0x9C27B0, pattern: [300, 120])
    ]
}
