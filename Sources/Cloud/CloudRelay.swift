import CloudKit
import Foundation

/// Private pairing over the user's own iCloud — no app server, no Firebase.
///
/// A bond is a **private CloudKit shared zone**: only the two paired people can read or write
/// inside it. Nobody else — not the developer, not other users, not Apple — can see the
/// touches, messages, heartbeats, location or photos. The owner creates a custom zone and a
/// `CKShare`; the partner accepts the share's invite link, which adds them as the one other
/// participant. Both sides then read and write records in that zone and are woken by a silent
/// push when the other writes.
///
/// Every step logs to the debug panel (NetLog) so a failure shows exactly where it happened
/// instead of a silent spinner.
final class CloudRelay {
    static let recordTypeBond = "Bond"
    static let recordTypeTouch = "Touch"
    static let recordTypeHeartbeat = "Heartbeat"
    static let recordTypeMessage = "Message"
    static let recordTypePresence = "Presence"
    static let recordTypeProfile = "Profile"

    private static let zonePrefix = "bond-"
    private static let rootName = "root"

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
        var partnerPhoto: Data?
    }

    private let container: CKContainer
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    /// Per-zone change tokens so we only fetch new records (in memory; a fresh launch
    /// re-reads recent records, which the app dedupes).
    private var changeTokens: [CKRecordZone.ID: CKServerChangeToken] = [:]

    init(containerIdentifier: String = AppConfig.cloudContainerID) {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    private func log(_ kind: NetLog.Entry.Kind, _ title: String, _ detail: String = "") {
        NetLog.shared.record(kind, title, detail)
    }

    // MARK: - Account

    func currentUserID() async throws -> String {
        try await container.userRecordID().recordName
    }

    func accountIsAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    func accountStatusMessage() async -> String? {
        let status = (try? await container.accountStatus()) ?? .couldNotDetermine
        switch status {
        case .available:
            return nil
        case .noAccount:
            return "You're not signed into iCloud on this iPhone. Open the Settings app, tap \"Sign in to your iPhone\" at the top, sign in with your Apple ID, and turn on iCloud Drive — then come back and pairing, photos and your heartbeat will work. (Apps can't open the iCloud sign-in for you.)"
        case .restricted:
            return "iCloud is restricted on this iPhone (Screen Time or a configuration profile). Allow iCloud to pair over it."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Give it a moment and try again."
        default:
            return "Can't reach iCloud. Check your internet connection and that you're signed into iCloud."
        }
    }

    // MARK: - Create a bond and its private share

    /// Creates a private bond: a fresh custom zone, a root record, and a `CKShare` saved
    /// together so the returned share's invite URL is ready to send. The partner accepts the
    /// link in their own copy of this app to join; nobody else can.
    func createBond(displayName: String) async throws -> (Bond, CKShare) {
        let zoneID = CKRecordZone.ID(zoneName: Self.zonePrefix + UUID().uuidString,
                                     ownerName: CKCurrentUserDefaultName)
        log(.send, "iCloud: creating bond zone", zoneID.zoneName)
        do {
            _ = try await privateDB.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        } catch {
            log(.fail, "iCloud: couldn't create zone", error.localizedDescription)
            throw error
        }

        let root = CKRecord(recordType: Self.recordTypeBond,
                            recordID: CKRecord.ID(recordName: Self.rootName, zoneID: zoneID))
        root["ownerName"] = displayName as CKRecordValue

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Bond Touch Beyond" as CKRecordValue
        share.publicPermission = .none   // invite-only: private to the two participants

        do {
            let result = try await privateDB.modifyRecords(saving: [root, share], deleting: [],
                                                           savePolicy: .allKeys, atomically: true)
            guard case .success(let savedShareRecord)? = result.saveResults[share.recordID],
                  let savedShare = savedShareRecord as? CKShare else {
                log(.fail, "iCloud: share didn't save", "no share in result")
                throw CloudRelayError.shareNotSaved
            }
            guard savedShare.url != nil else {
                log(.fail, "iCloud: share saved but has no invite URL", "")
                throw CloudRelayError.shareNotSaved
            }
            try? await installZoneSubscription(in: privateDB, zoneID: zoneID)
            log(.ok, "iCloud: bond created, invite ready", savedShare.url?.absoluteString ?? "")
            return (Bond(id: zoneID.zoneName, partnerName: "Pending…", isOwner: true, pending: true), savedShare)
        } catch let error as CloudRelayError {
            throw error
        } catch {
            log(.fail, "iCloud: couldn't save bond + share", error.localizedDescription)
            throw error
        }
    }

    // MARK: - Accept an invite (partner side)

    /// Accepts a private share invite the partner tapped. After this, the shared zone is in
    /// their shared database and both sides can read and write it.
    func acceptShare(_ metadata: CKShare.Metadata) async throws -> Bond {
        let zoneID = metadata.share.recordID.zoneID
        log(.send, "iCloud: accepting invite", zoneID.zoneName)
        do {
            _ = try await container.accept(metadata)
        } catch {
            log(.fail, "iCloud: accept failed", error.localizedDescription)
            throw error
        }
        try? await installZoneSubscription(in: sharedDB, zoneID: zoneID)
        let name = metadata.ownerIdentity.nameComponents
            .map { PersonNameComponentsFormatter().string(from: $0) } ?? "Partner"
        log(.ok, "iCloud: invite accepted", name)
        return Bond(id: zoneID.zoneName, partnerName: name.isEmpty ? "Partner" : name, isOwner: false)
    }

    // MARK: - Load bonds

    /// Every bond: zones this device created (private DB) and zones shared with it (shared DB).
    func loadBonds() async throws -> [Bond] {
        var bonds: [Bond] = []

        let privateZones = (try? await privateDB.allRecordZones()) ?? []
        for zone in privateZones where zone.zoneID.zoneName.hasPrefix(Self.zonePrefix) {
            // Pending until a participant other than the owner has accepted the share.
            var pending = true
            if let root = try? await privateDB.record(for: CKRecord.ID(recordName: Self.rootName, zoneID: zone.zoneID)),
               let shareRef = root.share,
               let shareRecord = try? await privateDB.record(for: shareRef.recordID),
               let share = shareRecord as? CKShare {
                pending = !share.participants.contains { $0.acceptanceStatus == .accepted && $0.role != .owner }
            }
            bonds.append(Bond(id: zone.zoneID.zoneName, partnerName: "Partner", isOwner: true, pending: pending))
        }

        let sharedZones = (try? await sharedDB.allRecordZones()) ?? []
        for zone in sharedZones where zone.zoneID.zoneName.hasPrefix(Self.zonePrefix) {
            var name = "Partner"
            if let root = try? await sharedDB.record(for: CKRecord.ID(recordName: Self.rootName, zoneID: zone.zoneID)),
               let ownerName = root["ownerName"] as? String, !ownerName.isEmpty {
                name = ownerName
            }
            bonds.append(Bond(id: zone.zoneID.zoneName, partnerName: name, isOwner: false, pending: false))
        }
        log(.ok, "iCloud: loaded bonds", "\(bonds.count) (\(bonds.filter { $0.pending }.count) pending)")
        return bonds
    }

    /// Removes a bond: the owner deletes its zone; a participant leaves by removing it from
    /// their shared DB.
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

    // MARK: - Sending

    private func db(for bond: Bond) -> CKDatabase { bond.isOwner ? privateDB : sharedDB }

    private func zoneID(forBond bond: Bond, in db: CKDatabase) async throws -> CKRecordZone.ID {
        let zones = try await db.allRecordZones()
        guard let match = zones.first(where: { $0.zoneID.zoneName == bond.id }) else {
            throw CloudRelayError.bondZoneNotFound
        }
        return match.zoneID
    }

    func sendTouch(_ touch: TouchMessage, bond: Bond) async throws {
        let database = db(for: bond)
        let zone = try await zoneID(forBond: bond, in: database)
        let record = CKRecord(recordType: Self.recordTypeTouch,
                              recordID: CKRecord.ID(recordName: touch.id.uuidString, zoneID: zone))
        record["senderID"] = touch.senderID as CKRecordValue
        // Stored as bytes, not an Int list: CloudKit's schema import can't declare a list
        // field, so the pattern is JSON-encoded into a BYTES field.
        record["pattern"] = (try? JSONEncoder().encode(touch.pattern)) as CKRecordValue? ?? (Data() as CKRecordValue)
        record["generation"] = touch.generation as CKRecordValue
        record["colorRGB"] = touch.colorRGB as CKRecordValue
        record["endColorRGB"] = touch.endColorRGB as CKRecordValue
        record["sentAt"] = touch.sentAt as CKRecordValue
        _ = try await database.modifyRecords(saving: [record], deleting: [])
    }

    func sendHeartbeat(bpm: Int, bond: Bond, senderID: String) async throws {
        let database = db(for: bond)
        let zone = try await zoneID(forBond: bond, in: database)
        let record = CKRecord(recordType: Self.recordTypeHeartbeat,
                              recordID: CKRecord.ID(recordName: "heartbeat-\(senderID)", zoneID: zone))
        record["senderID"] = senderID as CKRecordValue
        record["bpm"] = bpm as CKRecordValue
        record["sentAt"] = Date() as CKRecordValue
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    func sendChat(_ message: ChatMessage, bond: Bond) async throws {
        let database = db(for: bond)
        let zone = try await zoneID(forBond: bond, in: database)
        let record = CKRecord(recordType: Self.recordTypeMessage,
                              recordID: CKRecord.ID(recordName: message.id.uuidString, zoneID: zone))
        record["senderID"] = message.senderID as CKRecordValue
        record["kind"] = message.kind.rawValue as CKRecordValue
        record["text"] = message.text as CKRecordValue
        record["colorRGB"] = message.colorRGB as CKRecordValue
        record["sentAt"] = message.sentAt as CKRecordValue
        if message.kind == .image, let file = message.imageFile {
            record["image"] = CKAsset(fileURL: ChatArchive.imageURL(file))
        }
        _ = try await database.modifyRecords(saving: [record], deleting: [])
    }

    func sendPresence(online: Bool, bond: Bond, senderID: String,
                      latitude: Double? = nil, longitude: Double? = nil) async throws {
        let database = db(for: bond)
        let zone = try await zoneID(forBond: bond, in: database)
        let record = CKRecord(recordType: Self.recordTypePresence,
                              recordID: CKRecord.ID(recordName: "presence-\(senderID)", zoneID: zone))
        record["senderID"] = senderID as CKRecordValue
        record["online"] = (online ? 1 : 0) as CKRecordValue
        if let latitude, let longitude {
            record["lat"] = latitude as CKRecordValue
            record["lng"] = longitude as CKRecordValue
        }
        record["sentAt"] = Date() as CKRecordValue
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    func sendProfile(name: String, colorRGB: Int, photo: URL?, bond: Bond, senderID: String) async throws {
        let database = db(for: bond)
        let zone = try await zoneID(forBond: bond, in: database)
        let record = CKRecord(recordType: Self.recordTypeProfile,
                              recordID: CKRecord.ID(recordName: "profile-\(senderID)", zoneID: zone))
        record["senderID"] = senderID as CKRecordValue
        record["name"] = name as CKRecordValue
        record["colorRGB"] = colorRGB as CKRecordValue
        record["photo"] = photo.map { CKAsset(fileURL: $0) }
        record["sentAt"] = Date() as CKRecordValue
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    // MARK: - Receiving

    /// Fetches new records in the bond's zone since our last change token, ignoring our own.
    func fetchNewEvents(bond: Bond, myUserID: String) async throws -> RelayEvents {
        let database = db(for: bond)
        let zone = try await zoneID(forBond: bond, in: database)
        var events = RelayEvents()
        var newestHeartbeat: Date = .distantPast
        var newestPresence: Date = .distantPast
        var newestProfile: Date = .distantPast

        let changes = try await database.recordZoneChanges(inZoneWith: zone, since: changeTokens[zone])
        for modification in changes.modificationResultsByID.values {
            guard let record = try? modification.get().record,
                  let sender = record["senderID"] as? String, sender != myUserID,
                  let sentAt = record["sentAt"] as? Date else { continue }
            switch record.recordType {
            case Self.recordTypeTouch:
                let pattern: [Int]? = (record["pattern"] as? Data).flatMap { try? JSONDecoder().decode([Int].self, from: $0) }
                    ?? (record["pattern"] as? [Int])   // tolerate any older list-typed records
                if let pattern, let color = record["colorRGB"] as? Int,
                   let id = UUID(uuidString: record.recordID.recordName) {
                    let endColor = record["endColorRGB"] as? Int ?? color
                    events.touches.append(TouchMessage(id: id, bondID: bond.id, senderID: sender, pattern: pattern,
                                                       generation: record["generation"] as? Int ?? 2,
                                                       colorRGB: color, endColorRGB: endColor, sentAt: sentAt))
                }
            case Self.recordTypeMessage:
                if let id = UUID(uuidString: record.recordID.recordName) {
                    let kind = ChatMessage.Kind(rawValue: record["kind"] as? String ?? "text") ?? .text
                    var imageFile: String?
                    if kind == .image, let url = (record["image"] as? CKAsset)?.fileURL,
                       let data = try? Data(contentsOf: url) { imageFile = ChatArchive.saveImage(data) }
                    events.messages.append(ChatMessage(id: id, bondID: bond.id, senderID: sender, kind: kind,
                                                       text: record["text"] as? String ?? "",
                                                       colorRGB: record["colorRGB"] as? Int ?? 0xFF4081,
                                                       sentAt: sentAt, imageFile: imageFile))
                }
            case Self.recordTypeHeartbeat:
                if let bpm = record["bpm"] as? Int, sentAt > newestHeartbeat {
                    newestHeartbeat = sentAt; events.latestBPM = bpm; events.latestBPMAt = sentAt
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
                    if let url = (record["photo"] as? CKAsset)?.fileURL { events.partnerPhoto = try? Data(contentsOf: url) }
                }
            default: break
            }
        }
        changeTokens[zone] = changes.changeToken
        events.touches.sort { $0.sentAt < $1.sentAt }
        events.messages.sort { $0.sentAt < $1.sentAt }
        return events
    }

    // MARK: - Subscriptions

    /// Installs the per-zone silent-push subscription and, for the shared DB, a database-wide
    /// subscription so a newly accepted bond also wakes the app. Safe to call repeatedly.
    func installSharedDatabaseSubscription() async {
        let sub = CKDatabaseSubscription(subscriptionID: "shared-db-changes")
        let note = CKSubscription.NotificationInfo()
        note.shouldSendContentAvailable = true
        sub.notificationInfo = note
        _ = try? await sharedDB.modifySubscriptions(saving: [sub], deleting: [])
    }

    private func installZoneSubscription(in db: CKDatabase, zoneID: CKRecordZone.ID) async throws {
        let sub = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: "zone-\(zoneID.zoneName)")
        let note = CKSubscription.NotificationInfo()
        note.shouldSendContentAvailable = true   // silent push; we fetch on wake
        sub.notificationInfo = note
        _ = try await db.modifySubscriptions(saving: [sub], deleting: [])
    }
}

enum CloudRelayError: LocalizedError {
    case bondZoneNotFound
    case shareNotSaved
    var errorDescription: String? {
        switch self {
        case .bondZoneNotFound: return "That bond's iCloud zone wasn't found."
        case .shareNotSaved: return "iCloud didn't finish creating the invite. Try again."
        }
    }
}
