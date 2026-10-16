import CloudKit
import Foundation

/// Relays bonds and touches through the user's own iCloud account — no app server,
/// no Firebase. A bond is a shared CloudKit custom zone; touches are records written
/// into it. Both devices subscribe to the zone and are woken by a silent push when
/// the other writes a touch.
///
/// This replaces the original app's Firebase Realtime Database / FCM stack entirely.
/// Nothing here phones home to anyone but Apple's iCloud on the user's behalf.
final class CloudRelay {
    static let recordTypeTouch = "Touch"
    static let recordTypeBond = "Bond"
    static let subscriptionID = "bond-zone-changes"

    private let container: CKContainer
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    /// Server change tokens per zone, persisted so we only fetch new touches.
    private var changeTokens: [CKRecordZone.ID: CKServerChangeToken] = [:]

    init(containerIdentifier: String = "iCloud.com.coralcoder.bondtouchbeyond") {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    // MARK: - Account

    /// The current user's stable CloudKit record name, used as the touch sender id.
    func currentUserID() async throws -> String {
        let id = try await container.userRecordID()
        return id.recordName
    }

    func accountIsAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    // MARK: - Creating & sharing a bond

    /// Creates a new bond: a dedicated zone plus a root record, and returns a
    /// `CKShare` to hand to the system share sheet so a partner can join.
    func createBond(displayName: String) async throws -> (Bond, CKShare) {
        let zoneID = CKRecordZone.ID(zoneName: "bond-\(UUID().uuidString)", ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await privateDB.modifyRecordZones(saving: [zone], deleting: [])

        let rootID = CKRecord.ID(recordName: "root", zoneID: zoneID)
        let root = CKRecord(recordType: Self.recordTypeBond, recordID: rootID)
        root["ownerName"] = displayName as CKRecordValue

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Bond Touch" as CKRecordValue
        share.publicPermission = .none

        _ = try await privateDB.modifyRecords(saving: [root, share], deleting: [])
        try await installZoneSubscription(in: privateDB, zoneID: zoneID)

        let bond = Bond(id: zoneID.zoneName, partnerName: "Pending…", isOwner: true)
        return (bond, share)
    }

    /// Accepts an incoming share (partner side). Call from the scene delegate's
    /// `userDidAcceptCloudKitShareWith` metadata.
    func acceptShare(_ metadata: CKShare.Metadata) async throws -> Bond {
        _ = try await container.accept(metadata)
        let zoneID = metadata.share.recordID.zoneID
        try await installZoneSubscription(in: sharedDB, zoneID: zoneID)
        let name = metadata.ownerIdentity.nameComponents.map {
            PersonNameComponentsFormatter().string(from: $0)
        } ?? "Partner"
        return Bond(id: zoneID.zoneName, partnerName: name, isOwner: false)
    }

    // MARK: - Sending & receiving touches

    func sendTouch(_ touch: TouchMessage, bond: Bond) async throws {
        let db = bond.isOwner ? privateDB : sharedDB
        let zoneID = try await zoneID(forBond: bond, in: db)
        let record = CKRecord(
            recordType: Self.recordTypeTouch,
            recordID: CKRecord.ID(recordName: touch.id.uuidString, zoneID: zoneID)
        )
        record["senderID"] = touch.senderID as CKRecordValue
        record["pattern"] = touch.pattern as CKRecordValue
        record["colorRGB"] = touch.colorRGB as CKRecordValue
        record["sentAt"] = touch.sentAt as CKRecordValue
        _ = try await db.modifyRecords(saving: [record], deleting: [])
    }

    /// Fetches touches written since our last change token for the given bond.
    /// Returns only touches *not* sent by us, so we don't echo our own taps.
    func fetchNewTouches(bond: Bond, myUserID: String) async throws -> [TouchMessage] {
        let db = bond.isOwner ? privateDB : sharedDB
        let zoneID = try await zoneID(forBond: bond, in: db)
        var touches: [TouchMessage] = []

        let changes = try await db.recordZoneChanges(inZoneWith: zoneID, since: changeTokens[zoneID])
        for modification in changes.modificationResultsByID.values {
            guard let record = try? modification.get().record,
                  record.recordType == Self.recordTypeTouch,
                  let sender = record["senderID"] as? String, sender != myUserID,
                  let pattern = record["pattern"] as? [Int],
                  let color = record["colorRGB"] as? Int,
                  let sentAt = record["sentAt"] as? Date,
                  let id = UUID(uuidString: record.recordID.recordName)
            else { continue }
            touches.append(TouchMessage(id: id, senderID: sender, pattern: pattern, colorRGB: color, sentAt: sentAt))
        }
        changeTokens[zoneID] = changes.changeToken
        return touches.sorted { $0.sentAt < $1.sentAt }
    }

    // MARK: - Plumbing

    private func installZoneSubscription(in db: CKDatabase, zoneID: CKRecordZone.ID) async throws {
        let sub = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: "\(Self.subscriptionID)-\(zoneID.zoneName)")
        let note = CKSubscription.NotificationInfo()
        note.shouldSendContentAvailable = true   // silent push; we fetch on wake
        sub.notificationInfo = note
        _ = try await db.modifySubscriptions(saving: [sub], deleting: [])
    }

    private func zoneID(forBond bond: Bond, in db: CKDatabase) async throws -> CKRecordZone.ID {
        let zones = try await db.allRecordZones()
        if let match = zones.first(where: { $0.zoneID.zoneName == bond.id }) {
            return match.zoneID
        }
        throw CloudRelayError.bondZoneNotFound
    }
}

enum CloudRelayError: Error {
    case bondZoneNotFound
}
