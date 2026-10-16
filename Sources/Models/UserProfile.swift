import Foundation

/// The local user's profile — name, signature colour, and default vibration pattern.
/// Mirrors the original's profile setup (colour + vibration + username).
struct UserProfile: Codable, Equatable {
    var name: String
    var colorRGB: Int
    /// Default touch pattern (inter-tap gaps, ms) for a quick single send.
    var defaultPattern: [Int]

    static let empty = UserProfile(name: "", colorRGB: 0xFF4081, defaultPattern: [200, 200])

    var isComplete: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
}
