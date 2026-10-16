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
    static let recordTypeHeartbeat = "Heartbeat"
    static let recordTypeMessage = "Message"
    static let recordTypePresence = "Presence"
    static let recordTypeProfile = "Profile"
    static let subscriptionID = "bond-zone-changes"

    /// What a fetch pulled since the last change token, for one bond.
    struct RelayEvents {
        var touches: [TouchMessage] = []
        var messages: [ChatMessage] = []
        var latestBPM: Int?
        var latestBPMAt: Date?
        var presenceOnline: Bool?
        var presenceLastSeen: Date?
        var presenceLat: Double?
        var presenceLng: Double?
        var partnerName: String?
        var partnerColorRGB: Int?
        /// The partner's profile photo (JPEG), when their profile carries one.
        var partnerPhoto: Data?
    }

    private let container: CKContainer
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    /// Server change tokens per zone, persisted so we only fetch new touches.
    private var changeTokens: [CKRecordZone.ID: CKServerChangeToken] = [:]

    init(containerIdentifier: String = AppConfig.cloudContainerID) {
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
    /// Creates the bond zone and its root record and returns the root. The `CKShare` is
    /// created and saved later, inside `UICloudSharingController`'s preparation handler, so
    /// that the controller hands the system share sheet a share whose server URL is ready
    /// (otherwise the invite link preview spins forever).
    func createBond(displayName: String) async throws -> (Bond, CKRecord) {
        let zoneID = CKRecordZone.ID(zoneName: "bond-\(UUID().uuidString)", ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await privateDB.modifyRecordZones(saving: [zone], deleting: [])

        try await installZoneSubscription(in: privateDB, zoneID: zoneID)

        // Return an UNSAVED root; the share controller saves root + share together (the
        // supported "share a new record" flow). Saving the root first and re-saving it with
        // the share is what left the share sheet blank/grey.
        let rootID = CKRecord.ID(recordName: "root", zoneID: zoneID)
        let root = CKRecord(recordType: Self.recordTypeBond, recordID: rootID)
        root["ownerName"] = displayName as CKRecordValue

        let bond = Bond(id: zoneID.zoneName, partnerName: "Pending…", isOwner: true, pending: true)
        return (bond, root)
    }

    /// Deletes a bond: an owner's invite/zone is removed from the private DB; a bond shared
    /// with us is left by removing its zone from the shared DB.
    func deleteBond(_ bond: Bond) async throws {
        if bond.isOwner {
            let zoneID = CKRecordZone.ID(zoneName: bond.id, ownerName: CKCurrentUserDefaultName)
            _ = try await privateDB.modifyRecordZones(saving: [], deleting: [zoneID])
        } else {
            let zones = (try? await sharedDB.allRecordZones()) ?? []
            if let z = zones.first(where: { $0.zoneID.zoneName == bond.id }) {
                _ = try await sharedDB.modifyRecordZones(saving: [], deleting: [z.zoneID])
            }
        }
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

    /// Lists every bond the user has: zones they created (private DB) and zones shared
    /// with them (shared DB). Bond zone names start with "bond-".
    func loadBonds() async throws -> [Bond] {
        var bonds: [Bond] = []

        // Zones we created (private DB). These are "pending" invites until a partner has
        // actually accepted the share — an unaccepted invite is NOT shown as a partner.
        let privateZones = (try? await privateDB.allRecordZones()) ?? []
        for zone in privateZones where zone.zoneID.zoneName.hasPrefix("bond-") {
            var pending = true
            if let root = try? await privateDB.record(for: CKRecord.ID(recordName: "root", zoneID: zone.zoneID)),
               let shareRef = root.share,
               let shareRecord = try? await privateDB.record(for: shareRef.recordID),
               let share = shareRecord as? CKShare {
                pending = !share.participants.contains {
                    $0.acceptanceStatus == .accepted && $0.role != .owner
                }
            }
            bonds.append(Bond(id: zone.zoneID.zoneName, partnerName: "Partner",
                              isOwner: true, pending: pending))
        }

        // Zones shared with us (shared DB) — accepted by definition. The root's ownerName is
        // the partner (its creator).
        let sharedZones = (try? await sharedDB.allRecordZones()) ?? []
        for zone in sharedZones where zone.zoneID.zoneName.hasPrefix("bond-") {
            var name = "Partner"
            if let root = try? await sharedDB.record(for: CKRecord.ID(recordName: "root", zoneID: zone.zoneID)),
               let ownerName = root["ownerName"] as? String {
                name = ownerName
            }
            bonds.append(Bond(id: zone.zoneID.zoneName, partnerName: name, isOwner: false, pending: false))
        }
        return bonds
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
        record["generation"] = touch.generation as CKRecordValue
        record["colorRGB"] = touch.colorRGB as CKRecordValue
        record["endColorRGB"] = touch.endColorRGB as CKRecordValue
        record["sentAt"] = touch.sentAt as CKRecordValue
        _ = try await db.modifyRecords(saving: [record], deleting: [])
    }

    /// Sends one heartbeat (a button press) to the partner: one stable record per sender,
    /// overwritten each time, carrying the BPM and when it was sent.
    func sendHeartbeat(bpm: Int, bond: Bond, senderID: String) async throws {
        let db = bond.isOwner ? privateDB : sharedDB
        let zoneID = try await zoneID(forBond: bond, in: db)
        let record = CKRecord(
            recordType: Self.recordTypeHeartbeat,
            recordID: CKRecord.ID(recordName: "heartbeat-\(senderID)", zoneID: zoneID)
        )
        record["senderID"] = senderID as CKRecordValue
        record["bpm"] = bpm as CKRecordValue
        record["sentAt"] = Date() as CKRecordValue
        _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    // MARK: - Chat, presence, profile

    func sendChat(_ message: ChatMessage, bond: Bond) async throws {
        let db = bond.isOwner ? privateDB : sharedDB
        let zoneID = try await zoneID(forBond: bond, in: db)
        let record = CKRecord(recordType: Self.recordTypeMessage,
                              recordID: CKRecord.ID(recordName: message.id.uuidString, zoneID: zoneID))
        record["senderID"] = message.senderID as CKRecordValue
        record["kind"] = message.kind.rawValue as CKRecordValue
        record["text"] = message.text as CKRecordValue
        record["colorRGB"] = message.colorRGB as CKRecordValue
        record["sentAt"] = message.sentAt as CKRecordValue
        if message.kind == .image, let file = message.imageFile {
            record["image"] = CKAsset(fileURL: ChatArchive.imageURL(file))
        }
        _ = try await db.modifyRecords(saving: [record], deleting: [])
    }

    /// Publishes the user's presence (one stable record per sender, overwritten).
    func sendPresence(online: Bool, bond: Bond, senderID: String,
                      latitude: Double? = nil, longitude: Double? = nil) async throws {
        let db = bond.isOwner ? privateDB : sharedDB
        let zoneID = try await zoneID(forBond: bond, in: db)
        let record = CKRecord(recordType: Self.recordTypePresence,
                              recordID: CKRecord.ID(recordName: "presence-\(senderID)", zoneID: zoneID))
        record["senderID"] = senderID as CKRecordValue
        record["online"] = (online ? 1 : 0) as CKRecordValue
        if let latitude, let longitude {
            record["lat"] = latitude as CKRecordValue
            record["lng"] = longitude as CKRecordValue
        }
        record["sentAt"] = Date() as CKRecordValue
        _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    /// Publishes the user's profile (name, colour, photo) into the bond so the partner sees it.
    func sendProfile(name: String, colorRGB: Int, photo: URL?, bond: Bond, senderID: String) async throws {
        let db = bond.isOwner ? privateDB : sharedDB
        let zoneID = try await zoneID(forBond: bond, in: db)
        let record = CKRecord(recordType: Self.recordTypeProfile,
                              recordID: CKRecord.ID(recordName: "profile-\(senderID)", zoneID: zoneID))
        record["senderID"] = senderID as CKRecordValue
        record["name"] = name as CKRecordValue
        record["colorRGB"] = colorRGB as CKRecordValue
        record["photo"] = photo.map { CKAsset(fileURL: $0) }
        record["sentAt"] = Date() as CKRecordValue
        _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    /// Fetches touches and the partner's latest heartbeat since our last change token.
    /// Ignores anything we sent ourselves, so we don't echo our own taps/heartbeat.
    func fetchNewEvents(bond: Bond, myUserID: String) async throws -> RelayEvents {
        let db = bond.isOwner ? privateDB : sharedDB
        let zoneID = try await zoneID(forBond: bond, in: db)
        var events = RelayEvents()
        var newestHeartbeat: Date = .distantPast
        var newestPresence: Date = .distantPast
        var newestProfile: Date = .distantPast

        let changes = try await db.recordZoneChanges(inZoneWith: zoneID, since: changeTokens[zoneID])
        for modification in changes.modificationResultsByID.values {
            guard let record = try? modification.get().record,
                  let sender = record["senderID"] as? String, sender != myUserID,
                  let sentAt = record["sentAt"] as? Date
            else { continue }
            switch record.recordType {
            case Self.recordTypeTouch:
                if let pattern = record["pattern"] as? [Int],
                   let color = record["colorRGB"] as? Int,
                   let id = UUID(uuidString: record.recordID.recordName) {
                    let endColor = record["endColorRGB"] as? Int ?? color
                    events.touches.append(TouchMessage(id: id, senderID: sender, pattern: pattern,
                                                       generation: record["generation"] as? Int ?? 2,
                                                       colorRGB: color, endColorRGB: endColor, sentAt: sentAt))
                }
            case Self.recordTypeMessage:
                if let id = UUID(uuidString: record.recordID.recordName) {
                    let kind = ChatMessage.Kind(rawValue: record["kind"] as? String ?? "text") ?? .text
                    var imageFile: String?
                    if kind == .image, let url = (record["image"] as? CKAsset)?.fileURL,
                       let data = try? Data(contentsOf: url) {
                        imageFile = ChatArchive.saveImage(data)
                    }
                    events.messages.append(ChatMessage(
                        id: id, bondID: bond.id, senderID: sender, kind: kind,
                        text: record["text"] as? String ?? "",
                        colorRGB: record["colorRGB"] as? Int ?? 0xFF4081, sentAt: sentAt,
                        imageFile: imageFile))
                }
            case Self.recordTypeHeartbeat:
                if let bpm = record["bpm"] as? Int, sentAt > newestHeartbeat {
                    newestHeartbeat = sentAt
                    events.latestBPM = bpm
                    events.latestBPMAt = sentAt
                }
            case Self.recordTypePresence:
                if sentAt > newestPresence {
                    newestPresence = sentAt
                    events.presenceOnline = (record["online"] as? Int ?? 0) == 1
                    events.presenceLastSeen = sentAt
                    events.presenceLat = record["lat"] as? Double
                    events.presenceLng = record["lng"] as? Double
                }
            case Self.recordTypeProfile:
                if sentAt > newestProfile {
                    newestProfile = sentAt
                    events.partnerName = record["name"] as? String
                    events.partnerColorRGB = record["colorRGB"] as? Int
                    if let url = (record["photo"] as? CKAsset)?.fileURL {
                        events.partnerPhoto = try? Data(contentsOf: url)
                    }
                }
            default:
                break
            }
        }
        changeTokens[zoneID] = changes.changeToken
        events.touches.sort { $0.sentAt < $1.sentAt }
        events.messages.sort { $0.sentAt < $1.sentAt }
        return events
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
