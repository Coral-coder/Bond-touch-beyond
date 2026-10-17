import CloudKit
import CryptoKit
import Foundation

/// Connects two phones through iCloud with ONE link — no CloudKit sharing, no accept step.
/// A bond is a short random **code**; the invite link carries it.
///
/// There are no queries (so no indexes) and no subscriptions: every record has a name both
/// phones can work out from the code and their role — A created the invite, B joined it — so
/// each reads the other's records by name only. The schema is one record type, `BTItem`, with
/// one bytes field, `payload` (cloudkit.ckdb; must be deployed to Production). Everything in `payload` is AES-GCM encrypted under a key derived from the code
/// (BondCrypto), so the database holds only ciphertext. The partner's phone is woken by a
/// direct APNs push (APNsClient), not by CloudKit.
///
/// Records per bond (R is A or B; each phone only ever writes its own R):
///   <code>-bond        the inviter's name + iCloud id (written once by A)
///   <code>-R-pf        profile: name, colour, push token, photo hash
///   <code>-R-ph        profile photo
///   <code>-R-pr        presence: online, location
///   <code>-R-hb        latest heartbeat
///   <code>-R-head      newest event number
///   <code>-R-ev-<n>    event ring (touches + chat), slot n = number % 50
actor CloudRelay {
    static let recordType = "BTItem"
    static let ringSize = 50

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
        var partnerPushToken: String?
    }

    private let container: CKContainer
    private var db: CKDatabase { container.publicCloudDatabase }
    /// Change tag last seen per record, so an unchanged heartbeat/profile isn't re-reported.
    private var seenTags: [String: String] = [:]
    /// Photo hash last downloaded / uploaded per bond, so the photo moves only when it changes.
    private var seenPhotoHash: [String: String] = [:]
    private var writtenPhotoHash: [String: String] = [:]
    /// Sends run one after another so an event is always written before the head announcing it.
    private var sendTail: Task<Void, Never>?
    private var lastLoggedError = ""

    init(containerIdentifier: String = AppConfig.cloudContainerID) {
        container = CKContainer(identifier: containerIdentifier)
    }

    private func log(_ kind: NetLog.Entry.Kind, _ title: String, _ detail: String = "") {
        NetLog.shared.record(kind, title, detail)
    }

    private static func detail(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        return "CKError.\(ck.code.rawValue) — \(ck.localizedDescription)"
    }

    // MARK: - Account

    func currentUserID() async throws -> String { try await container.userRecordID().recordName }

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
        return normalize(code)
    }

    static func normalize(_ code: String) -> String {
        code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    }

    private static func newCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")   // no O/0/I/1
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }

    // MARK: - Record names

    private static func role(_ isOwner: Bool) -> String { isOwner ? "A" : "B" }
    private func id(_ code: String, _ suffix: String) -> CKRecord.ID { CKRecord.ID(recordName: "\(code)-\(suffix)") }
    private func bondID(_ code: String) -> CKRecord.ID { id(code, "bond") }
    /// One of this phone's records in `bond`.
    private func mine(_ bond: Bond, _ what: String) -> CKRecord.ID { id(bond.id, "\(Self.role(bond.isOwner))-\(what)") }
    /// One of the partner's records in `bond`.
    private func theirs(_ bond: Bond, _ what: String) -> CKRecord.ID { id(bond.id, "\(Self.role(!bond.isOwner))-\(what)") }

    // MARK: - Low-level read / write

    private func seal<T: Encodable>(_ value: T, _ code: String) throws -> Data {
        guard let data = BondCrypto.seal(value, code: code) else { throw CloudRelayError.crypto }
        return data
    }

    private func open<T: Decodable>(_ type: T.Type, _ record: CKRecord?, _ code: String) -> T? {
        guard let data = record?["payload"] as? Data else { return nil }
        return BondCrypto.open(type, from: data, code: code)
    }

    /// Creates or overwrites one record. Throws the record's own error — `modifyRecords`
    /// reports per-record failures (schema, permissions) in its results, not by throwing.
    private func put(_ recordID: CKRecord.ID, _ payload: Data) async throws {
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["payload"] = payload as CKRecordValue
        let result = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: false)
        if case .failure(let error) = result.saveResults[recordID] { throw error }
    }

    /// Fetches records by name; ones that don't exist yet are simply absent from the result.
    private func get(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord] {
        guard !ids.isEmpty else { return [:] }
        do {
            let results = try await db.records(for: ids)
            var out: [CKRecord.ID: CKRecord] = [:]
            for (rid, result) in results {
                switch result {
                case .success(let record): out[rid] = record
                case .failure(let error):
                    if (error as? CKError)?.code != .unknownItem { logOnce("iCloud read failed", error) }
                }
            }
            return out
        } catch {
            logOnce("iCloud read failed", error)
            throw error
        }
    }

    /// Logs an error once until a different one occurs (the poll runs every few seconds).
    private func logOnce(_ title: String, _ error: Error) {
        let text = Self.detail(error)
        guard text != lastLoggedError else { return }
        lastLoggedError = text
        log(.fail, title, text)
    }

    /// True the first time a record's current version is seen (by change tag).
    private func isNew(_ record: CKRecord) -> Bool {
        let name = record.recordID.recordName
        let tag = record.recordChangeTag ?? ""
        if seenTags[name] == tag { return false }
        seenTags[name] = tag
        return true
    }

    // MARK: - Create & join

    /// Creates a bond under a fresh code and returns it with its invite link. Also publishes
    /// this phone's profile right away, so the partner sees the inviter's name and push token
    /// the moment they join.
    func createBond(displayName: String, myUserID: String, colorRGB: Int, pushToken: String) async throws -> (Bond, URL) {
        var code = Self.newCode()
        if let found = try? await get([bondID(code)]), !found.isEmpty { code = Self.newCode() }
        log(.send, "iCloud: creating bond", code)
        let bond = Bond(id: code, partnerName: "Pending…", isOwner: true, pending: true)
        do {
            try await put(bondID(code), seal(BondPayload(name: displayName, ownerID: myUserID), code))
            try await put(mine(bond, "pf"), seal(ProfilePayload(name: displayName, colorRGB: colorRGB,
                                                                pushToken: pushToken, photoHash: nil), code))
        } catch {
            log(.fail, "iCloud: couldn't create bond", Self.detail(error))
            throw error
        }
        log(.ok, "iCloud: bond created, invite ready", Self.inviteURL(for: code).absoluteString)
        return (bond, Self.inviteURL(for: code))
    }

    /// Joins a bond by code as its second person (B). Writes this phone's profile straight
    /// away — that's how the inviter's phone learns we joined.
    func joinBond(code rawCode: String, displayName: String, colorRGB: Int, pushToken: String) async throws -> Bond {
        let code = Self.normalize(rawCode)
        log(.send, "iCloud: joining bond", code)
        let found: [CKRecord.ID: CKRecord]
        do { found = try await get([bondID(code)]) } catch {
            log(.fail, "iCloud: couldn't look up the code", Self.detail(error))
            throw error
        }
        guard let info = open(BondPayload.self, found[bondID(code)], code) else {
            log(.fail, "iCloud: no bond with that code", code)
            throw CloudRelayError.bondNotFound
        }
        let bond = Bond(id: code, partnerName: info.name, isOwner: false)
        do {
            try await put(mine(bond, "pf"), seal(ProfilePayload(name: displayName, colorRGB: colorRGB,
                                                                pushToken: pushToken, photoHash: nil), code))
        } catch {
            log(.fail, "iCloud: couldn't join bond", Self.detail(error))
            throw error
        }
        log(.ok, "iCloud: joined bond", "\(code) — with \(info.name)")
        return bond
    }

    /// Loads the bonds this phone belongs to (`roles`: code → created it here). A bond whose
    /// record is gone (the inviter unbonded) is left out; one that can't be reached right now
    /// is kept, so a bad connection at launch doesn't drop a partner.
    func loadBonds(roles: [String: Bool]) async -> [Bond] {
        var bonds: [Bond] = []
        for (code, isOwner) in roles {
            let probe = Bond(id: code, partnerName: "", isOwner: isOwner)
            guard let found = try? await get([bondID(code), theirs(probe, "pf")]) else {
                bonds.append(Bond(id: code, partnerName: "Partner", isOwner: isOwner))
                continue
            }
            guard let info = open(BondPayload.self, found[bondID(code)], code) else {
                log(.fail, "iCloud: bond \(code) no longer exists")
                continue
            }
            let profile = open(ProfilePayload.self, found[theirs(probe, "pf")], code)
            let name = profile?.name ?? (isOwner ? "Pending…" : info.name)
            bonds.append(Bond(id: code, partnerName: name, isOwner: isOwner, pending: isOwner && profile == nil))
        }
        return bonds
    }

    /// The partner's name once they've joined an invite we created; nil while still pending.
    func joinedPartnerName(_ bond: Bond) async -> String? {
        guard let found = try? await get([theirs(bond, "pf")]) else { return nil }
        return open(ProfilePayload.self, found[theirs(bond, "pf")], bond.id)?.name
    }

    func deleteBond(_ bond: Bond) async throws {
        var ids = ["pf", "ph", "pr", "hb", "head"].map { mine(bond, $0) }
        ids += (0..<Self.ringSize).map { mine(bond, "ev-\($0)") }
        if bond.isOwner { ids.append(bondID(bond.id)) }
        _ = try? await db.modifyRecords(saving: [], deleting: ids, savePolicy: .allKeys, atomically: false)
        UserDefaults.standard.removeObject(forKey: seqKey(bond.id))
        UserDefaults.standard.removeObject(forKey: seenKey(bond.id))
    }

    // MARK: - Sending (encrypted)

    func sendTouch(_ touch: TouchMessage, bond: Bond) async throws {
        let body = TouchBody(pattern: touch.pattern, generation: touch.generation,
                             colorRGB: touch.colorRGB, endColorRGB: touch.endColorRGB)
        try await sendEvent(bond: bond) { EventPayload(seq: $0, id: touch.id, sentAt: touch.sentAt, touch: body, chat: nil) }
    }

    func sendChat(_ message: ChatMessage, bond: Bond) async throws {
        var image: Data?
        if message.kind == .image, let file = message.imageFile {
            image = try? Data(contentsOf: ChatArchive.imageURL(file))
        }
        let body = ChatBody(kind: message.kind.rawValue, text: message.text, colorRGB: message.colorRGB, image: image)
        try await sendEvent(bond: bond) { EventPayload(seq: $0, id: message.id, sentAt: message.sentAt, touch: nil, chat: body) }
    }

    func sendHeartbeat(bpm: Int, bond: Bond, senderID: String) async throws {
        try await put(mine(bond, "hb"), seal(HeartbeatPayload(bpm: bpm, sentAt: Date()), bond.id))
    }

    func sendPresence(online: Bool, bond: Bond, senderID: String,
                      latitude: Double? = nil, longitude: Double? = nil) async throws {
        try await put(mine(bond, "pr"), seal(PresencePayload(online: online, lat: latitude, lng: longitude,
                                                             sentAt: Date()), bond.id))
    }

    func sendProfile(name: String, colorRGB: Int, photo: URL?, pushToken: String? = nil,
                     bond: Bond, senderID: String) async throws {
        let photoData = photo.flatMap { try? Data(contentsOf: $0) }
        let hash = photoData.map(Self.hash)
        if let photoData, let hash, writtenPhotoHash[bond.id] != hash {
            try await put(mine(bond, "ph"), seal(PhotoPayload(data: photoData), bond.id))
            writtenPhotoHash[bond.id] = hash
        }
        try await put(mine(bond, "pf"), seal(ProfilePayload(name: name, colorRGB: colorRGB,
                                                            pushToken: pushToken, photoHash: hash), bond.id))
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Event ring

    private func seqKey(_ code: String) -> String { "relay.seq.\(code)" }
    private func seenKey(_ code: String) -> String { "relay.seen.\(code)" }

    /// Writes one event (touch or chat) in order behind any send already in flight.
    private func sendEvent(bond: Bond, _ make: @escaping (Int) -> EventPayload) async throws {
        let previous = sendTail
        let task = Task { () async throws -> Void in
            await previous?.value
            try await self.writeEvent(bond: bond, make)
        }
        sendTail = Task { _ = await task.result }
        try await task.value
    }

    private func writeEvent(bond: Bond, _ make: (Int) -> EventPayload) async throws {
        let seq = await nextSeq(bond)
        // The event first, then the head that announces it — the partner never sees a head
        // pointing at an event that isn't there yet.
        try await put(mine(bond, "ev-\(seq % Self.ringSize)"), seal(make(seq), bond.id))
        try await put(mine(bond, "head"), seal(HeadPayload(seq: seq), bond.id))
    }

    /// Reserves this phone's next event number in `bond`, continuing from the server after a
    /// reinstall so numbers are never reused.
    private func nextSeq(_ bond: Bond) async -> Int {
        let key = seqKey(bond.id)
        if UserDefaults.standard.object(forKey: key) == nil {
            let server = open(HeadPayload.self, (try? await get([mine(bond, "head")]))?[mine(bond, "head")], bond.id)?.seq ?? 0
            if UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(server, forKey: key) }
        }
        let next = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(next, forKey: key)
        return next
    }

    // MARK: - Receiving (decrypt)

    /// Everything new from the partner since the last call: touches and chat from their event
    /// ring, plus their heartbeat, presence and profile when those changed. One or two fetches
    /// by name — cheap enough to poll every few seconds.
    func fetchNewEvents(bond: Bond, myUserID: String) async throws -> RelayEvents {
        let code = bond.id
        var events = RelayEvents()
        let found = try await get(["head", "hb", "pr", "pf"].map { theirs(bond, $0) })

        if let rec = found[theirs(bond, "hb")], isNew(rec), let p = open(HeartbeatPayload.self, rec, code) {
            events.latestBPM = p.bpm
            events.latestBPMAt = p.sentAt
        }
        if let p = open(PresencePayload.self, found[theirs(bond, "pr")], code) {
            events.presenceOnline = p.online
            events.presenceLastSeen = p.sentAt
            events.presenceLat = p.lat
            events.presenceLng = p.lng
        }
        if let rec = found[theirs(bond, "pf")], isNew(rec), let p = open(ProfilePayload.self, rec, code) {
            events.partnerName = p.name
            events.partnerColorRGB = p.colorRGB
            events.partnerPushToken = p.pushToken
            if let hash = p.photoHash, hash != seenPhotoHash[code],
               let photo = try? await get([theirs(bond, "ph")]),
               let image = open(PhotoPayload.self, photo[theirs(bond, "ph")], code) {
                events.partnerPhoto = image.data
                seenPhotoHash[code] = hash
            }
        }

        // The event ring: fetch every slot between what we've seen and their head.
        let head = open(HeadPayload.self, found[theirs(bond, "head")], code)?.seq ?? 0
        let lastSeen = UserDefaults.standard.object(forKey: seenKey(code)) as? Int ?? 0
        if head > lastSeen {
            let first = max(lastSeen + 1, head - Self.ringSize + 1)
            let wanted = (first...head).map { ($0, theirs(bond, "ev-\($0 % Self.ringSize)")) }
            let records = try await get(wanted.map { $0.1 })
            let partnerID = "\(code)-\(Self.role(!bond.isOwner))"   // never equals our own id
            for (seq, rid) in wanted {
                // A slot holding a different number was overwritten (more than 50 behind) — skip.
                guard let p = open(EventPayload.self, records[rid], code), p.seq == seq else { continue }
                if let t = p.touch {
                    events.touches.append(TouchMessage(id: p.id, bondID: code, senderID: partnerID, pattern: t.pattern,
                                                       generation: t.generation, colorRGB: t.colorRGB,
                                                       endColorRGB: t.endColorRGB, sentAt: p.sentAt))
                }
                if let c = p.chat {
                    let kind = ChatMessage.Kind(rawValue: c.kind) ?? .text
                    var imageFile: String?
                    if kind == .image, let img = c.image { imageFile = ChatArchive.saveImage(img) }
                    events.messages.append(ChatMessage(id: p.id, bondID: code, senderID: partnerID, kind: kind,
                                                       text: c.text, colorRGB: c.colorRGB, sentAt: p.sentAt,
                                                       imageFile: imageFile))
                }
            }
            UserDefaults.standard.set(head, forKey: seenKey(code))
        } else if head < lastSeen {
            UserDefaults.standard.set(head, forKey: seenKey(code))   // their numbering restarted
        }
        events.touches.sort { $0.sentAt < $1.sentAt }
        events.messages.sort { $0.sentAt < $1.sentAt }
        return events
    }
}

// Encrypted payload shapes (JSON, then AES-GCM sealed into `payload`).
private struct BondPayload: Codable { let name: String; let ownerID: String }
private struct ProfilePayload: Codable { let name: String; let colorRGB: Int; let pushToken: String?; let photoHash: String? }
private struct PhotoPayload: Codable { let data: Data }
private struct PresencePayload: Codable { let online: Bool; let lat: Double?; let lng: Double?; let sentAt: Date }
private struct HeartbeatPayload: Codable { let bpm: Int; let sentAt: Date }
private struct HeadPayload: Codable { let seq: Int }
private struct TouchBody: Codable { let pattern: [Int]; let generation: Int; let colorRGB: Int; let endColorRGB: Int }
private struct ChatBody: Codable { let kind: String; let text: String; let colorRGB: Int; let image: Data? }
private struct EventPayload: Codable {
    let seq: Int
    let id: UUID
    let sentAt: Date
    let touch: TouchBody?
    let chat: ChatBody?
}

enum CloudRelayError: LocalizedError {
    case bondNotFound
    case crypto
    var errorDescription: String? {
        switch self {
        case .bondNotFound: return "No bond with that code. Check it and try again."
        case .crypto: return "Couldn't encrypt the data for this bond."
        }
    }
}
