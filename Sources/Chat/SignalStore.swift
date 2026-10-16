import Foundation
import LibSignalClient

/// Persistent Signal protocol state for chat with original-app partners: this device's
/// identity, one-time / signed / Kyber pre-keys, partner identities and sessions. Saved as
/// one file in Application Support with complete file protection (encrypted at rest by iOS).
///
/// Trust policy mirrors the original app (`PrivateSpaceIdentityKeyStore`): receiving is
/// always trusted; when sending, a stored partner identity that differs is untrusted. A new
/// identity arriving in a received message replaces the stored one.
final class SignalStore: IdentityKeyStore, PreKeyStore, SignedPreKeyStore, KyberPreKeyStore, SessionStore {
    struct State: Codable {
        var identity: Data?            // IdentityKeyPair.serialize()
        var registrationId: UInt32 = 0
        var ownerUID: String = ""
        var signedPreKeyId: UInt32 = 0
        var preKeyLastId: UInt32 = 0
        var kyberPreKeyLastId: UInt32 = 0
        var preKeys: [UInt32: Data] = [:]
        var signedPreKeys: [UInt32: Data] = [:]
        var kyberPreKeys: [UInt32: Data] = [:]
        var lastResortKyberIds: Set<UInt32> = []
        var partnerIdentities: [String: Data] = [:]   // address name (bondId) → IdentityKey
        var sessions: [String: Data] = [:]            // address name → SessionRecord
        var kyberBaseKeysSeen: [String: [Data]] = [:]
        /// Keys are published to Firebase + the Bond API for this identity.
        var published = false
        /// Last time the one-time pre-key supply was checked (ms).
        var preKeyLastCheck: Double = 0
    }

    private(set) var state: State
    private let url: URL
    private let lock = NSLock()

    init(fileName: String = "signal-store.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(State.self, from: data) {
            state = s
        } else {
            state = State()
        }
    }

    func mutate(_ change: (inout State) -> Void) {
        lock.lock(); defer { lock.unlock() }
        change(&state)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    /// Forget everything (logout / account change).
    func reset() { mutate { $0 = State() } }

    var hasIdentity: Bool { state.identity != nil && state.registrationId != 0 }

    func hasSession(_ name: String) -> Bool { state.sessions[name] != nil }

    // MARK: IdentityKeyStore

    func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
        guard let data = state.identity else { throw SignalError.invalidState("no local identity") }
        return try IdentityKeyPair(bytes: data)
    }

    func localRegistrationId(context: StoreContext) throws -> UInt32 { state.registrationId }

    func saveIdentity(_ identity: IdentityKey, for address: ProtocolAddress,
                      context: StoreContext) throws -> IdentityChange {
        let new = identity.serialize()
        let old = state.partnerIdentities[address.name]
        mutate { $0.partnerIdentities[address.name] = new }
        return (old == nil || old == new) ? .newOrUnchanged : .replacedExisting
    }

    func isTrustedIdentity(_ identity: IdentityKey, for address: ProtocolAddress, direction: Direction,
                           context: StoreContext) throws -> Bool {
        guard direction == .sending, let stored = state.partnerIdentities[address.name] else { return true }
        return stored == identity.serialize()
    }

    func identity(for address: ProtocolAddress, context: StoreContext) throws -> IdentityKey? {
        try state.partnerIdentities[address.name].map { try IdentityKey(bytes: $0) }
    }

    // MARK: PreKeyStore

    func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
        guard let d = state.preKeys[id] else { throw SignalError.invalidKeyIdentifier("no prekey \(id)") }
        return try PreKeyRecord(bytes: d)
    }

    func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
        mutate { $0.preKeys[id] = record.serialize() }
    }

    func removePreKey(id: UInt32, context: StoreContext) throws {
        mutate { $0.preKeys.removeValue(forKey: id) }
    }

    // MARK: SignedPreKeyStore

    func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
        guard let d = state.signedPreKeys[id] else { throw SignalError.invalidKeyIdentifier("no signed prekey \(id)") }
        return try SignedPreKeyRecord(bytes: d)
    }

    func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
        mutate { $0.signedPreKeys[id] = record.serialize() }
    }

    // MARK: KyberPreKeyStore

    func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
        guard let d = state.kyberPreKeys[id] else { throw SignalError.invalidKeyIdentifier("no kyber prekey \(id)") }
        return try KyberPreKeyRecord(bytes: d)
    }

    func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
        mutate { $0.kyberPreKeys[id] = record.serialize() }
    }

    /// One-time Kyber keys are removed once used; the last-resort key is kept. A base key
    /// seen twice for the same key pair is a replay and is rejected.
    func markKyberPreKeyUsed(id: UInt32, signedPreKeyId: UInt32, baseKey: PublicKey,
                             context: StoreContext) throws {
        let slot = "\(id):\(signedPreKeyId)"
        let key = baseKey.serialize()
        if state.kyberBaseKeysSeen[slot]?.contains(key) == true {
            throw SignalError.invalidMessage("reused base key")
        }
        mutate {
            $0.kyberBaseKeysSeen[slot, default: []].append(key)
            if !$0.lastResortKyberIds.contains(id) { $0.kyberPreKeys.removeValue(forKey: id) }
        }
    }

    // MARK: SessionStore

    func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
        try state.sessions[address.name].map { try SessionRecord(bytes: $0) }
    }

    func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [SessionRecord] {
        try addresses.map { a in
            guard let d = state.sessions[a.name] else { throw SignalError.sessionNotFound("\(a)") }
            return try SessionRecord(bytes: d)
        }
    }

    func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
        mutate { $0.sessions[address.name] = record.serialize() }
    }
}
