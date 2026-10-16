import Foundation

/// A paired partner. Each partner is one CloudKit shared zone (a `Bond`), plus the live
/// presence and profile we learn about them. The app supports multiple partners.
struct Partner: Identifiable, Equatable {
    let bond: Bond
    var displayName: String
    var colorRGB: Int
    var online: Bool
    var lastSeen: Date?

    var id: String { bond.id }

    init(bond: Bond, displayName: String? = nil, colorRGB: Int = 0xFF4081,
         online: Bool = false, lastSeen: Date? = nil) {
        self.bond = bond
        self.displayName = displayName ?? bond.partnerName
        self.colorRGB = colorRGB
        self.online = online
        self.lastSeen = lastSeen
    }
}
