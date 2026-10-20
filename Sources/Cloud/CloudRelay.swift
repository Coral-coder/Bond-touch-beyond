import CloudKit
import CryptoKit
import Foundation

/// Connects two phones through iCloud with ONE link — no CloudKit sharing, no accept step.
/// A bond is a short random **code**; the invite link carries it.
///
/// Private between the two people: the code never goes to iCloud. The phones derive from it
/// (BondCrypto) an opaque **locator** that names the bond's records and a separate AES-GCM key
/// that seals every payload — so iCloud holds only meaningless IDs and ciphertext, and only the
/// two people with the link can read anything. Records can be read only by signed-in iCloud
/// users who know their exact names, and written only by their creator.
///
/// No queries (so no indexes) and no subscriptions: each phone works out the other's record
/// names from the locator and its role — A created the invite, B joined it — and fetches them
/// by name. The partner's phone is woken by a direct APNs push (APNsClient).
///
/// Records per bond (L = locator, R = A or B; each phone only ever writes its own R):
///   Bond       L-bond        the inviter's name + iCloud id (written once by A)
///   Profile    L-R-pf        name, colour, push token, photo hash
///   Photo      L-R-ph        profile photo
///   Presence   L-R-pr        online, location
///   Heartbeat  L-R-hb        latest heartbeat
///   Cursor     L-R-cur       newest touch and message numbers
///   Touch      L-R-t-<n>     touch ring, slot n = number % 50
///   Message    L-R-m-<n>     chat ring, slot n = number % 50
///   Profile    L-R-sx        the shared "Us" space (dates, likes, to-dos, notes, chess)
///   Profile    L-R-wb        the shared whiteboard
/// (The Us records reuse the Profile type — it only holds sealed bytes — so no schema change.)
/// The schema (cloudkit.ckdb) gives every type one encrypted BYTES field, `payload`.
actor CloudRelay {
    static let ringSize = 50

    struct RelayEvents {
        var touches: [TouchMessage] = []
        var messages: [ChatMessage] = []
        var latestBPM: Int?
        var latestBPMAt: Date?
        /// The partner's latest status snapshot (online, location, speed, batteries, bracelet).
        var presence: PresenceInfo?
        var partnerName: String?
        var partnerColorRGB: Int?
        var partnerPhoto: Data?
        var partnerPushToken: String?
        /// The highest number of *our* touches the partner's phone has received ("Seen").
        var partnerSeenTouch: Int?
        /// The same for our chat messages (read receipts).
        var partnerSeenMessage: Int?
        /// The partner's copy of the shared Touch Language, when their profile changed.
        var partnerMeanings: [TouchMeaning]?
        /// The partner's copy of the Us space and whiteboard, when they changed.
        var space: TogetherSpace?
        var board: Whiteboard?
    }

    /// The record kinds, each its own CloudKit record type.
    private enum Kind: String {
        case bond = "Bond", profile = "Profile", photo = "Photo", presence = "Presence"
        case heartbeat = "Heartbeat", cursor = "Cursor", touch = "Touch", message = "Message"
    }

    private let containerIdentifier: String
    /// Made on first use, not at launch: demo mode (an unsigned simulator build with no iCloud
    /// entitlement) never touches iCloud, and creating the container there stops the app.
    private lazy var container = CKContainer(identifier: containerIdentifier)
    private var db: CKDatabase {
        get throws {
            if Self.offline { throw CKError(.notAuthenticated) }
            return container.publicCloudDatabase
        }
    }
    /// Demo mode (screenshots in the unsigned simulator build) never talks to iCloud.
    private static let offline = ProcessInfo.processInfo.arguments.contains("-demo")
    /// Change tag last seen per record, so an unchanged heartbeat/profile isn't re-reported.
    private var seenTags: [String: String] = [:]
    /// Photo hash last downloaded / uploaded per bond, so the photo moves only when it changes.
    private var seenPhotoHash: [String: String] = [:]
    private var writtenPhotoHash: [String: String] = [:]
    /// Sends run one after another so an event is always written before the cursor announcing it.
    private var sendTail: Task<Void, Never>?
    private var lastLoggedError = ""

    init(containerIdentifier: String = AppConfig.cloudContainerID) {
        self.containerIdentifier = containerIdentifier
    }

    private func log(_ kind: NetLog.Entry.Kind, _ title: String, _ detail: String = "") {
        NetLog.shared.record(kind, title, detail)
    }

    private static func detail(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        return "CKError.\(ck.code.rawValue) — \(ck.localizedDescription)"
    }

    // MARK: - Account

    func currentUserID() async throws -> String {
        if Self.offline { throw CKError(.notAuthenticated) }
        return try await container.userRecordID().recordName
    }

    func accountStatusMessage() async -> String? {
        let status = Self.offline ? .couldNotDetermine : ((try? await container.accountStatus()) ?? .couldNotDetermine)
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

    // MARK: - Record names (opaque: derived from the code, never the code itself)

    private struct Ref {
        let id: CKRecord.ID
        let kind: Kind
    }

    private static func role(_ isOwner: Bool) -> String { isOwner ? "A" : "B" }

    private func ref(_ code: String, _ suffix: String, _ kind: Kind) -> Ref {
        Ref(id: CKRecord.ID(recordName: "\(BondCrypto.locator(forCode: code))-\(suffix)"), kind: kind)
    }
    private func bondRef(_ code: String) -> Ref { ref(code, "bond", .bond) }
    /// One of this phone's records in `bond`.
    private func mine(_ bond: Bond, _ what: String, _ kind: Kind) -> Ref {
        ref(bond.id, "\(Self.role(bond.isOwner))-\(what)", kind)
    }
    /// One of the partner's records in `bond`.
    private func theirs(_ bond: Bond, _ what: String, _ kind: Kind) -> Ref {
        ref(bond.id, "\(Self.role(!bond.isOwner))-\(what)", kind)
    }
    private func slot(_ seq: Int) -> Int { seq % Self.ringSize }

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
    private func put(_ ref: Ref, _ payload: Data) async throws {
        let record = CKRecord(recordType: ref.kind.rawValue, recordID: ref.id)
        record["payload"] = payload as CKRecordValue
        let result = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: false)
        if case .failure(let error) = result.saveResults[ref.id] { throw error }
    }

    /// Fetches records by name; ones that don't exist yet are simply absent from the result.
    private func get(_ refs: [Ref]) async throws -> [CKRecord.ID: CKRecord] {
        guard !refs.isEmpty else { return [:] }
        do {
            let results = try await db.records(for: refs.map(\.id))
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
        if let found = try? await get([bondRef(code)]), !found.isEmpty { code = Self.newCode() }
        log(.send, "iCloud: creating bond")
        let bond = Bond(id: code, partnerName: "Pending…", isOwner: true, pending: true)
        do {
            try await put(bondRef(code), seal(BondPayload(name: displayName, ownerID: myUserID), code))
            try await put(mine(bond, "pf", .profile), seal(ProfilePayload(name: displayName, colorRGB: colorRGB,
                                                                          pushToken: pushToken, photoHash: nil), code))
        } catch {
            log(.fail, "iCloud: couldn't create bond", Self.detail(error))
            throw error
        }
        log(.ok, "iCloud: bond created, invite ready")
        return (bond, Self.inviteURL(for: code))
    }

    /// Joins a bond by code as its second person (B). Writes this phone's profile straight
    /// away — that's how the inviter's phone learns we joined.
    func joinBond(code rawCode: String, displayName: String, colorRGB: Int, pushToken: String) async throws -> Bond {
        let code = Self.normalize(rawCode)
        log(.send, "iCloud: joining bond")
        let found: [CKRecord.ID: CKRecord]
        do { found = try await get([bondRef(code)]) } catch {
            log(.fail, "iCloud: couldn't look up the code", Self.detail(error))
            throw error
        }
        guard let info = open(BondPayload.self, found[bondRef(code).id], code) else {
            log(.fail, "iCloud: no bond with that code")
            throw CloudRelayError.bondNotFound
        }
        let bond = Bond(id: code, partnerName: info.name, isOwner: false)
        do {
            try await put(mine(bond, "pf", .profile), seal(ProfilePayload(name: displayName, colorRGB: colorRGB,
                                                                          pushToken: pushToken, photoHash: nil), code))
        } catch {
            log(.fail, "iCloud: couldn't join bond", Self.detail(error))
            throw error
        }
        log(.ok, "iCloud: joined bond", "with \(info.name)")
        return bond
    }

    /// Loads the bonds this phone belongs to (`roles`: code → created it here). A bond whose
    /// record is gone (the inviter unbonded) is left out; one that can't be reached right now
    /// is kept, so a bad connection at launch doesn't drop a partner.
    func loadBonds(roles: [String: Bool]) async -> [Bond] {
        var bonds: [Bond] = []
        for (code, isOwner) in roles {
            let probe = Bond(id: code, partnerName: "", isOwner: isOwner)
            let partnerProfile = theirs(probe, "pf", .profile)
            guard let found = try? await get([bondRef(code), partnerProfile]) else {
                bonds.append(Bond(id: code, partnerName: "Partner", isOwner: isOwner))
                continue
            }
            guard let info = open(BondPayload.self, found[bondRef(code).id], code) else {
                log(.fail, "iCloud: a bond no longer exists")
                continue
            }
            let profile = open(ProfilePayload.self, found[partnerProfile.id], code)
            let name = profile?.name ?? (isOwner ? "Pending…" : info.name)
            bonds.append(Bond(id: code, partnerName: name, isOwner: isOwner, pending: isOwner && profile == nil))
        }
        return bonds
    }

    /// The partner's name once they've joined an invite we created; nil while still pending.
    func joinedPartnerName(_ bond: Bond) async -> String? {
        let profile = theirs(bond, "pf", .profile)
        guard let found = try? await get([profile]) else { return nil }
        return open(ProfilePayload.self, found[profile.id], bond.id)?.name
    }

    func deleteBond(_ bond: Bond) async throws {
        var refs = [mine(bond, "pf", .profile), mine(bond, "ph", .photo), mine(bond, "pr", .presence),
                    mine(bond, "hb", .heartbeat), mine(bond, "cur", .cursor)]
        refs += (0..<Self.ringSize).map { mine(bond, "t-\($0)", .touch) }
        refs += (0..<Self.ringSize).map { mine(bond, "m-\($0)", .message) }
        if bond.isOwner { refs.append(bondRef(bond.id)) }
        _ = try? await db.modifyRecords(saving: [], deleting: refs.map(\.id), savePolicy: .allKeys, atomically: false)
        for key in [seqKey(bond.id, .touch), seqKey(bond.id, .message), seenKey(bond.id, .touch), seenKey(bond.id, .message)] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Sending (encrypted)

    /// Sends a touch; returns its number in this phone's touch ring (for Seen).
    @discardableResult
    func sendTouch(_ touch: TouchMessage, bond: Bond) async throws -> Int {
        let body = TouchPayload(id: touch.id, sentAt: touch.sentAt, pattern: touch.pattern, generation: touch.generation,
                                colorRGB: touch.colorRGB, endColorRGB: touch.endColorRGB,
                                meaningLabel: touch.meaningLabel, meaningEmoji: touch.meaningEmoji,
                                heartbeatBPM: touch.heartbeatBPM)
        return try await sendEvent(.touch, bond: bond) { (seq: Int) -> TouchPayload in var b = body; b.seq = seq; return b }
    }

    /// Sends a chat message; returns its number in this phone's message ring (read receipts).
    @discardableResult
    func sendChat(_ message: ChatMessage, bond: Bond) async throws -> Int {
        var image: Data?
        if message.kind == .image, let file = message.imageFile {
            image = try? Data(contentsOf: ChatArchive.imageURL(file))
        }
        let body = MessagePayload(id: message.id, sentAt: message.sentAt, kind: message.kind.rawValue,
                                  text: message.text, colorRGB: message.colorRGB, image: image)
        return try await sendEvent(.message, bond: bond) { (seq: Int) -> MessagePayload in var b = body; b.seq = seq; return b }
    }

    func sendHeartbeat(bpm: Int, bond: Bond, senderID: String) async throws {
        try await put(mine(bond, "hb", .heartbeat), seal(HeartbeatPayload(bpm: bpm, sentAt: Date()), bond.id))
    }

    /// Writes this phone's full status snapshot for the partner (it replaces the previous one).
    func sendPresence(_ info: PresenceInfo, bond: Bond) async throws {
        var info = info
        info.sentAt = Date()
        try await put(mine(bond, "pr", .presence), seal(info, bond.id))
    }

    func sendProfile(name: String, colorRGB: Int, photo: URL?, pushToken: String? = nil,
                     meanings: [TouchMeaning]? = nil, bond: Bond, senderID: String) async throws {
        let photoData = photo.flatMap { try? Data(contentsOf: $0) }
        let hash = photoData.map(Self.hash)
        if let photoData, let hash, writtenPhotoHash[bond.id] != hash {
            try await put(mine(bond, "ph", .photo), seal(PhotoPayload(data: photoData), bond.id))
            writtenPhotoHash[bond.id] = hash
        }
        try await put(mine(bond, "pf", .profile), seal(ProfilePayload(name: name, colorRGB: colorRGB,
                                                                      pushToken: pushToken, photoHash: hash,
                                                                      meanings: meanings), bond.id))
    }

    /// This phone's copy of the Us space / whiteboard (the partner merges it into theirs).
    func sendSpace(_ space: TogetherSpace, bond: Bond) async throws {
        try await put(mine(bond, "sx", .profile), seal(space, bond.id))
    }

    func sendBoard(_ board: Whiteboard, bond: Bond) async throws {
        try await put(mine(bond, "wb", .profile), seal(board, bond.id))
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Touch & message rings

    private func seqKey(_ code: String, _ kind: Kind) -> String { "relay.seq.\(kind.rawValue).\(code)" }
    private func seenKey(_ code: String, _ kind: Kind) -> String { "relay.seen.\(kind.rawValue).\(code)" }

    /// Writes one touch or message in order behind any send already in flight.
    private func sendEvent<P: Encodable>(_ kind: Kind, bond: Bond, _ make: @escaping (Int) -> P) async throws -> Int {
        let previous = sendTail
        let task = Task { () async throws -> Int in
            await previous?.value
            return try await self.writeEvent(kind, bond: bond, make)
        }
        sendTail = Task { _ = await task.result }
        return try await task.value
    }

    private func writeEvent<P: Encodable>(_ kind: Kind, bond: Bond, _ make: (Int) -> P) async throws -> Int {
        let seq = await nextSeq(kind, bond)
        let what = kind == .touch ? "t-\(slot(seq))" : "m-\(slot(seq))"
        // The event first, then the cursor that announces it — the partner never sees a
        // cursor pointing at an event that isn't there yet.
        try await put(mine(bond, what, kind), seal(make(seq), bond.id))
        try await writeCursor(bond)
        return seq
    }

    /// This phone's cursor: its newest numbers, plus how far it has received the partner's touches.
    private func writeCursor(_ bond: Bond) async throws {
        let cursor = CursorPayload(touch: UserDefaults.standard.integer(forKey: seqKey(bond.id, .touch)),
                                   message: UserDefaults.standard.integer(forKey: seqKey(bond.id, .message)),
                                   seenTouch: UserDefaults.standard.integer(forKey: seenKey(bond.id, .touch)),
                                   seenMessage: UserDefaults.standard.integer(forKey: seenKey(bond.id, .message)))
        try await put(mine(bond, "cur", .cursor), seal(cursor, bond.id))
    }

    /// Reserves this phone's next touch or message number in `bond`, continuing from the
    /// server after a reinstall so numbers are never reused.
    private func nextSeq(_ kind: Kind, _ bond: Bond) async -> Int {
        await loadCounters(bond)
        let key = seqKey(bond.id, kind)
        let next = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(next, forKey: key)
        return next
    }

    /// Makes sure this phone knows its own newest numbers (from the server after a reinstall),
    /// so a cursor it writes never rewinds them.
    private func loadCounters(_ bond: Bond) async {
        let touchKey = seqKey(bond.id, .touch), messageKey = seqKey(bond.id, .message)
        if UserDefaults.standard.object(forKey: touchKey) == nil || UserDefaults.standard.object(forKey: messageKey) == nil {
            let cursorRef = mine(bond, "cur", .cursor)
            let server = open(CursorPayload.self, (try? await get([cursorRef]))?[cursorRef.id], bond.id)
            if UserDefaults.standard.object(forKey: touchKey) == nil { UserDefaults.standard.set(server?.touch ?? 0, forKey: touchKey) }
            if UserDefaults.standard.object(forKey: messageKey) == nil { UserDefaults.standard.set(server?.message ?? 0, forKey: messageKey) }
        }
    }

    /// The slots between what we've seen and the partner's newest number (at most one ring).
    private func pendingRange(_ kind: Kind, code: String, newest: Int) -> ClosedRange<Int>? {
        let lastSeen = UserDefaults.standard.object(forKey: seenKey(code, kind)) as? Int ?? 0
        if newest < lastSeen { UserDefaults.standard.set(newest, forKey: seenKey(code, kind)) }   // they restarted
        guard newest > lastSeen else { return nil }
        return max(lastSeen + 1, newest - Self.ringSize + 1)...newest
    }

    // MARK: - Receiving (decrypt)

    /// Everything new from the partner since the last call: touches and chat from their rings,
    /// plus their heartbeat, presence and profile when those changed. One or two fetches by
    /// name — cheap enough to poll every few seconds.
    func fetchNewEvents(bond: Bond, myUserID: String) async throws -> RelayEvents {
        let code = bond.id
        var events = RelayEvents()
        let cursorRef = theirs(bond, "cur", .cursor), heartbeatRef = theirs(bond, "hb", .heartbeat)
        let presenceRef = theirs(bond, "pr", .presence), profileRef = theirs(bond, "pf", .profile)
        let spaceRef = theirs(bond, "sx", .profile), boardRef = theirs(bond, "wb", .profile)
        let found = try await get([cursorRef, heartbeatRef, presenceRef, profileRef, spaceRef, boardRef])
        if let rec = found[spaceRef.id], isNew(rec) { events.space = open(TogetherSpace.self, rec, code) }
        if let rec = found[boardRef.id], isNew(rec) { events.board = open(Whiteboard.self, rec, code) }

        if let rec = found[heartbeatRef.id], isNew(rec), let p = open(HeartbeatPayload.self, rec, code) {
            events.latestBPM = p.bpm
            events.latestBPMAt = p.sentAt
        }
        events.presence = open(PresenceInfo.self, found[presenceRef.id], code)
        if let rec = found[profileRef.id], isNew(rec), let p = open(ProfilePayload.self, rec, code) {
            events.partnerName = p.name
            events.partnerColorRGB = p.colorRGB
            events.partnerPushToken = p.pushToken
            events.partnerMeanings = p.meanings
            let photoRef = theirs(bond, "ph", .photo)
            if let hash = p.photoHash, hash != seenPhotoHash[code],
               let photo = try? await get([photoRef]),
               let image = open(PhotoPayload.self, photo[photoRef.id], code) {
                events.partnerPhoto = image.data
                seenPhotoHash[code] = hash
            }
        }

        // The rings: fetch every slot between what we've seen and their newest numbers.
        let cursor = open(CursorPayload.self, found[cursorRef.id], code) ?? CursorPayload(touch: 0, message: 0)
        events.partnerSeenTouch = cursor.seenTouch
        events.partnerSeenMessage = cursor.seenMessage
        let touchRange = pendingRange(.touch, code: code, newest: cursor.touch)
        let messageRange = pendingRange(.message, code: code, newest: cursor.message)
        let touchRefs = touchRange.map { r in r.map { ($0, theirs(bond, "t-\(slot($0))", .touch)) } } ?? []
        let messageRefs = messageRange.map { r in r.map { ($0, theirs(bond, "m-\(slot($0))", .message)) } } ?? []
        if !touchRefs.isEmpty || !messageRefs.isEmpty {
            let records = try await get(touchRefs.map(\.1) + messageRefs.map(\.1))
            let partnerID = "\(code)-\(Self.role(!bond.isOwner))"   // never equals our own id
            for (seq, r) in touchRefs {
                // A slot holding a different number was overwritten (> 50 behind) — skip it.
                guard let t = open(TouchPayload.self, records[r.id], code), t.seq == seq else { continue }
                events.touches.append(TouchMessage(id: t.id, bondID: code, senderID: partnerID, pattern: t.pattern,
                                                   generation: t.generation, colorRGB: t.colorRGB,
                                                   endColorRGB: t.endColorRGB, sentAt: t.sentAt,
                                                   meaningLabel: t.meaningLabel, meaningEmoji: t.meaningEmoji,
                                                   heartbeatBPM: t.heartbeatBPM))
            }
            for (seq, r) in messageRefs {
                guard let m = open(MessagePayload.self, records[r.id], code), m.seq == seq else { continue }
                let kind = ChatMessage.Kind(rawValue: m.kind) ?? .text
                var imageFile: String?
                if kind == .image, let img = m.image { imageFile = ChatArchive.saveImage(img) }
                events.messages.append(ChatMessage(id: m.id, bondID: code, senderID: partnerID, kind: kind,
                                                   text: m.text, colorRGB: m.colorRGB, sentAt: m.sentAt,
                                                   imageFile: imageFile))
            }
            if let touchRange { UserDefaults.standard.set(touchRange.upperBound, forKey: seenKey(code, .touch)) }
            if let messageRange { UserDefaults.standard.set(messageRange.upperBound, forKey: seenKey(code, .message)) }
            // Tell the partner their touches and messages arrived (their "Seen").
            if touchRange != nil || messageRange != nil {
                await loadCounters(bond)
                try? await writeCursor(bond)
            }
        }
        events.touches.sort { $0.sentAt < $1.sentAt }
        events.messages.sort { $0.sentAt < $1.sentAt }
        return events
    }
}

// Encrypted payload shapes (JSON, then AES-GCM sealed into `payload`).
private struct BondPayload: Codable { let name: String; let ownerID: String }
private struct ProfilePayload: Codable {
    let name: String; let colorRGB: Int; let pushToken: String?; let photoHash: String?
    /// The Touch Language this phone shares with the partner (optional: older builds).
    var meanings: [TouchMeaning]? = nil
}
private struct PhotoPayload: Codable { let data: Data }
/// A phone's status snapshot, shared (encrypted) with its partner and shown on their card.
/// Every field but `online` is optional so older and newer builds read each other's.
struct PresenceInfo: Codable, Equatable {
    var online: Bool
    /// Shared location (only while location sharing is on) and when that fix was taken.
    var lat: Double? = nil
    var lng: Double? = nil
    var locationAt: Date? = nil
    /// Speed in metres per second at `locationAt`, when known.
    var speed: Double? = nil
    /// Phone battery 0…1 and whether it's charging.
    var phoneBattery: Double? = nil
    var phoneCharging: Bool? = nil
    /// Whether the bracelet is connected (the partner then sends silent pushes), its battery
    /// percentage, and when it was last connected.
    var bracelet: Bool? = nil
    var braceletBattery: Int? = nil
    var braceletLastConnected: Date? = nil
    /// The Apple Watch is standing in for the bracelet (it plays touches itself), so the
    /// partner's pushes can stay quiet too.
    var watchStandIn: Bool? = nil
    /// The weather where this phone is (if it shares it): town, now, the next hours and days.
    var weather: WeatherInfo? = nil
    /// How they're feeling and their personal battery (if they share it).
    var mood: MoodShare? = nil
    /// Notification groups switched off on this phone (Settings → Notifications): the
    /// partner's phone sends those silently.
    var muted: [String]? = nil
    /// When this snapshot was written — the phone's last check-in.
    var sentAt = Date()
}
private struct HeartbeatPayload: Codable { let bpm: Int; let sentAt: Date }
/// A phone's newest touch / message numbers, and the partner's touches it has received
/// (so the partner can mark theirs Seen; optional so older builds read it).
private struct CursorPayload: Codable {
    let touch: Int; let message: Int; var seenTouch: Int? = nil; var seenMessage: Int? = nil
}
private struct TouchPayload: Codable {
    var seq = 0
    let id: UUID
    let sentAt: Date
    let pattern: [Int]
    let generation: Int
    let colorRGB: Int
    let endColorRGB: Int
    /// The saved meaning it was sent as, so the partner sees the name over it.
    var meaningLabel: String? = nil
    var meaningEmoji: String? = nil
    /// Set when it's a heartbeat (the pattern is then the EKG).
    var heartbeatBPM: Int? = nil
}
private struct MessagePayload: Codable {
    var seq = 0
    let id: UUID
    let sentAt: Date
    let kind: String
    let text: String
    let colorRGB: Int
    let image: Data?
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
