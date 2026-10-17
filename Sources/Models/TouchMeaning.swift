import Foundation

/// A saved "meaning" for a touch — the original app lets partners agree that a given
/// rhythm/colour means something ("thinking of you", "goodnight"). Sending a meaning
/// sends its pattern + colour.
struct TouchMeaning: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var emoji: String
    /// Start colour of the touch's two-stop gradient.
    var colorRGB: Int
    /// End colour of the gradient (equals `colorRGB` for a single-colour touch).
    var endColorRGB: Int
    var pattern: [Int]   // inter-tap gaps in ms
    /// Freshly added meanings show a "New" badge until sent, as in the original.
    var isNew: Bool = false
    /// The meaning's id on the original Bond backend, for meanings synced with an
    /// original-app partner (nil for iCloud-only meanings).
    var serverID: String? = nil
    /// Pattern format: 3 = 50 ms position samples (touch bar), nil/2 = on/off milliseconds.
    var generation: Int? = nil
    /// Starred in the Touch Library (synced with the original backend's `favourite`).
    /// Optional so meanings saved before this field existed still load.
    var favourite: Bool? = nil

    var touchGeneration: Int { generation == 3 ? 3 : 2 }

    init(id: UUID = UUID(), label: String, emoji: String, colorRGB: Int,
         endColorRGB: Int? = nil, pattern: [Int], isNew: Bool = false, serverID: String? = nil,
         generation: Int? = nil) {
        self.id = id
        self.label = label
        self.emoji = emoji
        self.colorRGB = colorRGB
        self.endColorRGB = endColorRGB ?? colorRGB
        self.pattern = pattern
        self.isNew = isNew
        self.serverID = serverID
        self.generation = generation
    }

    /// The original app's library starts empty; meanings come from the partner adding them
    /// (and server recommendations). No hardcoded defaults.
    static let starters: [TouchMeaning] = []
}
