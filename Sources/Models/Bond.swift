import Foundation

/// A pairing between two people. In CloudKit terms this is a shared custom zone:
/// the creator owns it, the partner accepts a `CKShare` into it, and touches are
/// records written into that zone by either side.
struct Bond: Identifiable, Equatable {
    let id: String          // zone name / share root record name
    var partnerName: String // display name of the other person
    var isOwner: Bool       // true if this device created the bond
    /// True for an invite the user created that no partner has accepted yet. Pending
    /// bonds are not shown as active partners — only as a cancellable invite.
    var pending: Bool = false
    /// True for a bond on the original Bond Touch backend (a partner using the original
    /// app); its `id` is the server `bondId`. False for an iCloud (CloudKit zone) bond.
    var legacy: Bool = false
}
