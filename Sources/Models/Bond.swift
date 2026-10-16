import Foundation

/// A pairing between two people. In CloudKit terms this is a shared custom zone:
/// the creator owns it, the partner accepts a `CKShare` into it, and touches are
/// records written into that zone by either side.
struct Bond: Identifiable, Equatable {
    let id: String          // zone name / share root record name
    var partnerName: String // display name of the other person
    var isOwner: Bool       // true if this device created the bond
}
