import Foundation

/// The local user's profile — name, signature colour, and default vibration pattern.
/// Mirrors the original's profile setup (colour + vibration + username).
struct UserProfile: Codable, Equatable {
    var name: String
    var colorRGB: Int
    /// Default touch pattern (inter-tap gaps, ms) for a quick single send.
    var defaultPattern: [Int]
    /// What you share about yourself with every partner (optional: older saves have none).
    var about: AboutMe? = nil

    static let empty = UserProfile(name: "", colorRGB: 0xFF4081, defaultPattern: [200, 200])

    var isComplete: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Your profile as partners see it: a line about you, pronouns, birthday, and the things you
/// like ("Favourite flowers: peonies"). Sent with your profile to every partner.
struct AboutMe: Codable, Equatable {
    var bio: String = ""
    var pronouns: String = ""
    var birthday: Date? = nil
    var items: [AboutItem] = []

    var isEmpty: Bool {
        bio.trimmingCharacters(in: .whitespaces).isEmpty && pronouns.isEmpty && birthday == nil && items.isEmpty
    }

    /// One thing you like (or need them to know): a label and its value.
    struct AboutItem: Codable, Equatable, Identifiable {
        var id = UUID()
        var label: String
        var value: String
    }

    /// Ideas for things to add, shown as one-tap chips.
    static let ideas = ["Favourite food", "Favourite flowers", "Favourite colour", "Coffee order", "Love language",
                        "Clothes size", "Shoe size", "Ring size", "Favourite film", "Favourite song",
                        "Dream trip", "Allergies", "Pet peeve", "Comfort snack"]
}
