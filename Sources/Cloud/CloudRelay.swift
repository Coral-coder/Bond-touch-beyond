import CloudKit
import Foundation

/// Connects two phones through a shared iCloud database with ONE link — no CloudKit sharing,
/// no accept step. A bond is a short random **code**; the invite link carries it. Both phones
/// read and write records in the app's public database, filtered by that code.
///
/// It is still private: every payload is end-to-end encrypted with a key derived from the
/// code (see BondCrypto), which only the two people with the link have. The database stores
/// only ciphertext, an opaque sender id, a timestamp, and the code used to group records.
final class CloudRelay {
    static let recordTypeBond = "Bond"
    static let recordTypeTouch = "Touch"
    static let recordTypeHeartbeat = "Heartbeat"
    static let recordTypeMessage = "Message"
    static let recordTypePresence = "Presence"
    static let recordTypeProfile = "Profile"

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
    private var db: CKDatabase { container.publicCloudDatabase }
    private var lastSeen: [String: Date] = [:]

    init(containerIdentifier: String = AppConfig.cloudContainerID) {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    private func log(_ kind: NetLog.Entry.Kind, _ title: String, _ detail: String = "") {
        NetLog.shared.record(kind, title, detail)
    }

    private func ckDetail(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        return "CKError.\(ck.code.rawValue) — \(ck.localizedDescription)"
    }

    // MARK: - Account

    func currentUserID() async throws -> String { try await container.userRecordID().recordName }
    func accountIsAvailable() async -> Bool { (try? await container.accountStatus()) == .available }

    func accountStatusMessage() async -> String? {
        let status = (try? await container.accountStatus()) ?? .couldNotDetermine
        switch status {
        case .available: return nil
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

    // MARK: - Codes & links

    static func inviteURL(for code: String) -> URL { URL(string: "bondtouchbeyond://join?code=\(code)")! }

    static func code(fromURL url: URL) -> String? {
        guard url.scheme == "bondtouchbeyond", url.host == "join",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }
        return code.uppercased()
    }

    private static func newCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")   // no O/0/I/1
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }

    private func bondRecordID(_ code: String) -> CKRecord.ID { CKRecord.ID(recordName: "bond-\(code)") }

    // MARK: - Create & join

    /// Creates a bond under a fresh code and returns the code + invite link. The partner joins
    /// by opening the link or typing the code — no acceptance step.
    func createBond(displayName: String, myUserID: String) async throws -> (Bond, URL) {
        var code = Self.newCode()
        if (try? await db.record(for: bondRecordID(code))) != nil { code = Self.newCode() }
        log(.send, "iCloud: creating bond", code)
        let record = CKRecord(recordType: Self.recordTypeBond, recordID: bondRecordID(code))
        record["bondID"] = code as CKRecordValue
        record["ownerID"] = myUserID as CKRecordValue
        record["payload"] = (BondCrypto.seal(["name": displayName], code: code) ?? Data()) as CKRecordValue
        record["sentAt"] = Date() as CKRecordValue
        do {
            _ = try await db.save(record)
        } catch {
            log(.fail, "iCloud: couldn't create bond", ckDetail(error)); throw error
        }
        try? await installSubscription(code: code)
        log(.ok, "iCloud: bond created, invite ready", Self.inviteURL(for: code).absoluteString)
        return (Bond(id: code, partnerName: "Pending…", isOwner: true, pending: true), Self.inviteURL(for: code))
    }

    /// Joins a bond by code. Verifies it exists and returns it.
    func joinBond(code rawCode: String, displayName: String, myUserID: String) async throws -> Bond {
        let code = rawCode.uppercased()
        log(.send, "iCloud: joining bond", code)
        guard let record = try? await db.record(for: bondRecordID(code)) else {
            log(.fail, "iCloud: no bond with that code", code)
            throw CloudRelayError.bondNotFound
        }
        try? await installSubscription(code: code)
        let ownerID = record["ownerID"] as? String ?? ""
        let ownerName = (record["payload"] as? Data).flatMap { BondCrypto.open([String: String].self, from: $0, code: code)?["name"] } ?? "Partner"
        log(.ok, "iCloud: joined bond", code)
        return Bond(id: code, partnerName: ownerID == myUserID ? "Partner" : ownerName, isOwner: ownerID == myUserID)
    }

    /// Loads known bonds (by code), filling in the partner's name from their profile.
    func loadBonds(codes: [String], myUserID: String) async throws -> [Bond] {
        var bonds: [Bond] = []
        for code in codes {
            guard let record = try? await db.record(for: bondRecordID(code)) else { continue }
            let ownerID = record["ownerID"] as? String ?? ""
            let isOwner = ownerID == myUserID
            let partnerProfile = try? await latestProfilePayload(code: code, otherThan: myUserID)
            let ownerName = (record["payload"] as? Data).flatMap { BondCrypto.open([String: String].self, from: $0, code: code)?["name"] }
            let name = (partnerProfile?["name"] as? String) ?? (isOwner ? "Pending…" : (ownerName ?? "Partner"))
            bonds.append(Bond(id: code, partnerName: name, isOwner: isOwner, pending: isOwner && partnerProfile == nil))
        }
        return bonds
    }

    func deleteBond(_ bond: Bond) async throws {
        if bond.isOwner { _ = try? await db.deleteRecord(withID: bondRecordID(bond.id)) }
    }

    // MARK: - Sending (encrypted)

    private func newRecord(_ type: String, name: String, code: String, senderID: String, payload: Data, sentAt: Date = Date()) -> CKRecord {
        let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name))
        record["bondID"] = code as CKRecordValue
        record["senderID"] = senderID as CKRecordValue
        record["sentAt"] = sentAt as CKRecordValue
        record["payload"] = payload as CKRecordValue
        return record
    }

    /// Writes a record whose name is reused across updates (presence, heartbeat, profile —
    /// one per sender, "latest wins"). A plain `save` of a freshly built record with an
    /// existing name throws `serverRecordChanged`; `.allKeys` overwrites the server copy, so
    /// repeated updates (every foreground, every heartbeat) actually land.
    private func upsert(_ record: CKRecord) async throws {
        _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: true)
    }

    func sendTouch(_ touch: TouchMessage, bond: Bond) async throws {
        let body = TouchPayload(pattern: touch.pattern, generation: touch.generation,
                                colorRGB: touch.colorRGB, endColorRGB: touch.endColorRGB)
        guard let payload = BondCrypto.seal(body, code: bond.id) else { return }
        let record = newRecord(Self.recordTypeTouch, name: "t-\(bond.id)-\(touch.id.uuidString)",
                               code: bond.id, senderID: touch.senderID, payload: payload, sentAt: touch.sentAt)
        _ = try await db.save(record)
    }

    func sendHeartbeat(bpm: Int, bond: Bond, senderID: String) async throws {
        guard let payload = BondCrypto.seal(["bpm": bpm], code: bond.id) else { return }
        try await upsert(newRecord(Self.recordTypeHeartbeat, name: "hb-\(bond.id)-\(senderID)",
                                   code: bond.id, senderID: senderID, payload: payload))
    }

    func sendChat(_ message: ChatMessage, bond: Bond) async throws {
        var imageData: Data?
        if message.kind == .image, let file = message.imageFile {
            imageData = try? Data(contentsOf: ChatArchive.imageURL(file))
        }
        let body = MessagePayload(kind: message.kind.rawValue, text: message.text,
                                  colorRGB: message.colorRGB, image: imageData)
        guard let payload = BondCrypto.seal(body, code: bond.id) else { return }
        _ = try await db.save(newRecord(Self.recordTypeMessage, name: "m-\(bond.id)-\(message.id.uuidString)",
                                        code: bond.id, senderID: message.senderID, payload: payload, sentAt: message.sentAt))
    }

    func sendPresence(online: Bool, bond: Bond, senderID: String,
                      latitude: Double? = nil, longitude: Double? = nil) async throws {
        let body = PresencePayload(online: online, lat: latitude, lng: longitude)
        guard let payload = BondCrypto.seal(body, code: bond.id) else { return }
        try await upsert(newRecord(Self.recordTypePresence, name: "pr-\(bond.id)-\(senderID)",
                                   code: bond.id, senderID: senderID, payload: payload))
    }

    func sendProfile(name: String, colorRGB: Int, photo: URL?, bond: Bond, senderID: String) async throws {
        let photoData = photo.flatMap { try? Data(contentsOf: $0) }
        let body = ProfilePayload(name: name, colorRGB: colorRGB, photo: photoData)
        guard let payload = BondCrypto.seal(body, code: bond.id) else { return }
        try await upsert(newRecord(Self.recordTypeProfile, name: "pf-\(bond.id)-\(senderID)",
                                   code: bond.id, senderID: senderID, payload: payload))
    }

    // MARK: - Receiving (decrypt)

    func fetchNewEvents(bond: Bond, myUserID: String) async throws -> RelayEvents {
        let code = bond.id
        let since = lastSeen[code] ?? .distantPast
        var events = RelayEvents()
        var newest = since
        var newestHeartbeat: Date = .distantPast, newestPresence: Date = .distantPast, newestProfile: Date = .distantPast

        for type in [Self.recordTypeTouch, Self.recordTypeMessage, Self.recordTypeHeartbeat,
                     Self.recordTypePresence, Self.recordTypeProfile] {
            let predicate = NSPredicate(format: "bondID == %@ AND sentAt > %@", code, since as NSDate)
            let query = CKQuery(recordType: type, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "sentAt", ascending: true)]
            let records = try await allRecords(matching: query)
            for record in records {
                guard let sender = record["senderID"] as? String, sender != myUserID,
                      let sentAt = record["sentAt"] as? Date, let data = record["payload"] as? Data else { continue }
                newest = max(newest, sentAt)
                switch type {
                case Self.recordTypeTouch:
                    if let p = BondCrypto.open(TouchPayload.self, from: data, code: code) {
                        let id = UUID(uuidString: String(record.recordID.recordName.dropFirst("t-\(code)-".count))) ?? UUID()
                        events.touches.append(TouchMessage(id: id, bondID: code, senderID: sender, pattern: p.pattern,
                                                           generation: p.generation, colorRGB: p.colorRGB,
                                                           endColorRGB: p.endColorRGB, sentAt: sentAt))
                    }
                case Self.recordTypeMessage:
                    if let p = BondCrypto.open(MessagePayload.self, from: data, code: code) {
                        let kind = ChatMessage.Kind(rawValue: p.kind) ?? .text
                        var imageFile: String?
                        if kind == .image, let img = p.image { imageFile = ChatArchive.saveImage(img) }
                        let id = UUID(uuidString: String(record.recordID.recordName.dropFirst("m-\(code)-".count))) ?? UUID()
                        events.messages.append(ChatMessage(id: id, bondID: code, senderID: sender, kind: kind,
                                                           text: p.text, colorRGB: p.colorRGB, sentAt: sentAt, imageFile: imageFile))
                    }
                case Self.recordTypeHeartbeat:
                    if sentAt > newestHeartbeat, let p = BondCrypto.open([String: Int].self, from: data, code: code), let bpm = p["bpm"] {
                        newestHeartbeat = sentAt; events.latestBPM = bpm; events.latestBPMAt = sentAt
                    }
                case Self.recordTypePresence:
                    if sentAt > newestPresence, let p = BondCrypto.open(PresencePayload.self, from: data, code: code) {
                        newestPresence = sentAt
                        events.presenceOnline = p.online; events.presenceLastSeen = sentAt
                        events.presenceLat = p.lat; events.presenceLng = p.lng
                    }
                case Self.recordTypeProfile:
                    if sentAt > newestProfile, let p = BondCrypto.open(ProfilePayload.self, from: data, code: code) {
                        newestProfile = sentAt
                        events.partnerName = p.name; events.partnerColorRGB = p.colorRGB; events.partnerPhoto = p.photo
                    }
                default: break
                }
            }
        }
        lastSeen[code] = newest
        events.touches.sort { $0.sentAt < $1.sentAt }
        events.messages.sort { $0.sentAt < $1.sentAt }
        return events
    }

    // MARK: - Plumbing

    private func latestProfilePayload(code: String, otherThan myUserID: String) async throws -> [String: Any]? {
        let predicate = NSPredicate(format: "bondID == %@", code)
        let query = CKQuery(recordType: Self.recordTypeProfile, predicate: predicate)
        let records = try await allRecords(matching: query)
        guard let record = records.first(where: { ($0["senderID"] as? String) != myUserID }),
              let data = record["payload"] as? Data,
              let p = BondCrypto.open(ProfilePayload.self, from: data, code: code) else { return nil }
        return ["name": p.name, "colorRGB": p.colorRGB]
    }

    private func allRecords(matching query: CKQuery) async throws -> [CKRecord] {
        var out: [CKRecord] = []
        var result = try await db.records(matching: query, resultsLimit: 200)
        func collect(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (_, r) in matches { if case .success(let rec) = r { out.append(rec) } }
        }
        collect(result.matchResults)
        while let cursor = result.queryCursor {
            result = try await db.records(continuingMatchFrom: cursor, resultsLimit: 200)
            collect(result.matchResults)
        }
        return out
    }

    /// A silent push ONLY for records in this exact bond (predicate `bondID == code`), so a
    /// phone is woken only by its own pair's touches — never by any other bond's activity.
    private func installSubscription(code: String) async throws {
        let predicate = NSPredicate(format: "bondID == %@", code)
        let sub = CKQuerySubscription(recordType: Self.recordTypeTouch, predicate: predicate,
                                      subscriptionID: "touch-\(code)", options: [.firesOnRecordCreation])
        let note = CKSubscription.NotificationInfo()
        note.shouldSendContentAvailable = true
        sub.notificationInfo = note
        _ = try? await db.modifySubscriptions(saving: [sub], deleting: [])
    }

    /// Makes sure a per-bond push subscription exists for each known code (called on launch),
    /// so a phone listens to exactly its bonds and nothing else.
    func ensureSubscriptions(codes: [String]) async {
        for code in codes { try? await installSubscription(code: code) }
    }
}

// Encrypted payload shapes (JSON, then AES-GCM sealed).
private struct TouchPayload: Codable { let pattern: [Int]; let generation: Int; let colorRGB: Int; let endColorRGB: Int }
private struct MessagePayload: Codable { let kind: String; let text: String; let colorRGB: Int; let image: Data? }
private struct PresencePayload: Codable { let online: Bool; let lat: Double?; let lng: Double? }
private struct ProfilePayload: Codable { let name: String; let colorRGB: Int; let photo: Data? }

enum CloudRelayError: LocalizedError {
    case bondNotFound
    var errorDescription: String? {
        switch self {
        case .bondNotFound: return "No bond with that code. Check it and try again."
        }
    }
}
