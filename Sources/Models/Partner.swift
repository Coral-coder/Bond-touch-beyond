import Foundation

/// A paired partner. Each partner is one CloudKit shared zone (a `Bond`), plus the live
/// presence and profile we learn about them. The app supports multiple partners.
struct Partner: Identifiable, Equatable {
    let bond: Bond
    var displayName: String
    var colorRGB: Int
    var online: Bool
    var lastSeen: Date?
    /// Last shared location (Presence), if the partner is sharing.
    var latitude: Double?
    var longitude: Double?

    var id: String { bond.id }

    init(bond: Bond, displayName: String? = nil, colorRGB: Int = 0xFF4081,
         online: Bool = false, lastSeen: Date? = nil,
         latitude: Double? = nil, longitude: Double? = nil) {
        self.bond = bond
        self.displayName = displayName ?? bond.partnerName
        self.colorRGB = colorRGB
        self.online = online
        self.lastSeen = lastSeen
        self.latitude = latitude
        self.longitude = longitude
    }
}
