import Foundation
import LibSignalClient

/// End-to-end encrypted chat with partners on the original Bond Touch app, byte-compatible
/// with it (see docs/CHAT_PROTOCOL.md):
/// - Signal protocol (LibSignalClient), partner address = `(bondId, device 1)`.
/// - Public keys published as raw bytes at `crypto/<uid>/<name>_<id>` in Firebase Storage,
///   their ids at `PUT bond/api/v3/signal/1`.
/// - Message content = Android-Base64 (76-char lines + trailing newline) of
///   `[CiphertextMessage type byte] + serialized message`; photos are the same envelope as
///   raw bytes in the `bond-touch-galleries` bucket, the chat content being the file name.
///
/// This device has its own identity: private keys are never uploaded by either app, so the
/// original app's identity can't be restored. Enabling chat here publishes new keys and
/// opens a fresh session with each partner (a NewSession message); their app accepts the
/// new identity from that first message.
final class BondChat {
    let store = SignalStore()
    private let ctx = NullContext()

    static let deviceId: UInt32 = 1
    static let batch: UInt32 = 15
    static let maxId: UInt32 = 0xFFFFFF

    enum ChatError: LocalizedError {
        case partnerNotReady, partnerNeedsUpdate, noSession, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .partnerNotReady: return "Your partner's chat keys aren't published yet (they need to open Private Space once)."
            case .partnerNeedsUpdate: return "Your partner's app needs updating to support encrypted chat."
            case .noSession: return "No encrypted session with this partner yet."
            case .http(let code, let body): return "Chat server error \(code): \(body)"
            }
        }
    }

    struct SignalInfo {
        var registrationId = -1, signedPreKeyId = -1
        var nextPreKeyId = -1, lastPreKeyId = -1
        var nextKyberPreKeyId = -1, lastKyberPreKeyId = -1

        init() {}
        init(_ j: [String: Any]) {
            func i(_ k: String) -> Int { (j[k] as? NSNumber)?.intValue ?? -1 }
            registrationId = i("registrationId"); signedPreKeyId = i("signedPreKeyId")
            nextPreKeyId = i("nextPreKeyId"); lastPreKeyId = i("lastPreKeyId")
            nextKyberPreKeyId = i("nextKyberPreKeyId"); lastKyberPreKeyId = i("lastKyberPreKeyId")
        }
    }

    // MARK: - REST

    @discardableResult
    private func api(_ path: String, _ method: String, token: String,
                     body: [String: Any]? = nil) async throws -> (Int, Any?) {
        var req = URLRequest(url: BondBackend.apiBase.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
        return (code, json)
    }

    @discardableResult
    private func check(_ r: (Int, Any?)) throws -> Any? {
        guard r.0 < 400 else {
            let body = r.1.flatMap { try? JSONSerialization.data(withJSONObject: $0) }.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw ChatError.http(r.0, body)
        }
        return r.1
    }

    private func selfSignalInfo(token: String) async throws -> SignalInfo {
        let r = try await api("bond/api/v3/signal/\(Self.deviceId)", "GET", token: token)
        if r.0 == 404 { return SignalInfo() }
        return SignalInfo((try check(r) as? [String: Any]) ?? [:])
    }

    // MARK: - Base64 / envelope

    /// `android.util.Base64.encode(bytes, DEFAULT)`: 76-char lines, `\n` after each, trailing `\n`.
    static func androidBase64(_ data: Data) -> String {
        data.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed]) + "\n"
    }

    static func decodeBase64(_ s: String) -> Data? {
        Data(base64Encoded: s, options: .ignoreUnknownCharacters)
    }

    private func address(_ bondId: String) throws -> ProtocolAddress {
        try ProtocolAddress(name: bondId, deviceId: Self.deviceId)
    }

    func encrypt(_ plaintext: Data, bondId: String) throws -> Data {
        guard store.hasSession(bondId) else { throw ChatError.noSession }
        let msg = try signalEncrypt(message: plaintext, for: try address(bondId),
                                    sessionStore: store, identityStore: store, context: ctx)
        return Data([msg.messageType.rawValue]) + msg.serialize()
    }

    func decrypt(_ envelope: Data, bondId: String) throws -> Data {
        guard let type = envelope.first else { throw SignalError.invalidMessage("empty") }
        let body = Data(envelope.dropFirst())
        let addr = try address(bondId)
        if type == CiphertextMessage.MessageType.preKey.rawValue {
            return try signalDecryptPreKey(message: try PreKeySignalMessage(bytes: body), from: addr,
                                           sessionStore: store, identityStore: store, preKeyStore: store,
                                           signedPreKeyStore: store, kyberPreKeyStore: store, context: ctx)
        }
        return try signalDecrypt(message: try SignalMessage(bytes: body), from: addr,
                                 sessionStore: store, identityStore: store, context: ctx)
    }

    // MARK: - Keys

    /// Generates this device's identity and keys (once per account) and publishes them:
    /// public keys to `crypto/<uid>/`, then their ids with `PUT bond/api/v3/signal/1`.
    func initKeysIfNeeded(uid: String, token: String) async throws {
        if store.hasIdentity, store.state.ownerUID == uid, store.state.published { return }
        let info = try await selfSignalInfo(token: token)

        if !store.hasIdentity || store.state.ownerUID != uid {
            let identity = IdentityKeyPair.generate()
            let reg = UInt32.random(in: 1...2_147_483_646)
            store.reset()
            store.mutate { $0.identity = identity.serialize(); $0.registrationId = reg; $0.ownerUID = uid }
        }
        let identity = try store.identityKeyPair(context: ctx)
        let reg = store.state.registrationId

        let preStart = UInt32(max(info.lastPreKeyId, info.nextPreKeyId, Int(store.state.preKeyLastId), 0) + 1)
        let kyberStart = UInt32(max(info.lastKyberPreKeyId, info.nextKyberPreKeyId, Int(store.state.kyberPreKeyLastId), 0) + 1)
        guard preStart + Self.batch < Self.maxId, kyberStart + Self.batch + 1 < Self.maxId else {
            throw SignalError.invalidState("pre-key ids exhausted")
        }

        var uploads: [(String, Data)] = [("identity_\(reg)", identity.identityKey.serialize())]
        uploads += try makePreKeys(from: preStart)
        uploads += try makeKyberKeys(from: kyberStart, identity: identity)

        let lastResortId = kyberStart + Self.batch
        let lastResort = try kyberRecord(id: lastResortId, identity: identity)
        store.mutate { $0.lastResortKyberIds.insert(lastResortId) }
        uploads.append(("lastResortKyberKey_\(lastResortId)", lastResort.publicKey))
        uploads.append(("lastResortKyberKeySignature_\(lastResortId)", lastResort.signature))

        let spkId = UInt32.random(in: 0..<Self.maxId)
        let spkPriv = PrivateKey.generate()
        let spkSig = identity.privateKey.generateSignature(message: spkPriv.publicKey.serialize())
        try store.storeSignedPreKey(try SignedPreKeyRecord(id: spkId, timestamp: Self.nowMs, privateKey: spkPriv, signature: spkSig),
                                    id: spkId, context: ctx)
        uploads.append(("signedPreKey_\(spkId)", spkPriv.publicKey.serialize()))
        uploads.append(("signedPreKeySignature_\(spkId)", spkSig))

        try await uploadAll(uploads, uid: uid, token: token)
        try check(try await api("bond/api/v3/signal/\(Self.deviceId)", "PUT", token: token, body: [
            "registrationId": Int(reg), "signedPreKeyId": Int(spkId),
            "nextPreKeyId": Int(preStart), "lastPreKeyId": Int(preStart + Self.batch - 1),
            "nextKyberPreKeyId": Int(kyberStart), "lastKyberPreKeyId": Int(kyberStart + Self.batch - 1),
            "lastResortKyberPreKeyId": Int(lastResortId)
        ]))
        store.mutate {
            $0.signedPreKeyId = spkId
            $0.preKeyLastId = preStart + Self.batch - 1
            $0.kyberPreKeyLastId = lastResortId
            $0.published = true
        }
    }

    /// Tops up one-time keys when fewer than 3 remain (`PATCH bond/api/v3/signal/1`).
    func replenishIfNeeded(uid: String, token: String) async throws {
        guard store.state.published, store.state.ownerUID == uid else { return }
        let info = try await selfSignalInfo(token: token)
        guard info.registrationId != -1 else { store.mutate { $0.published = false }; return }
        let lowEC = info.nextPreKeyId + 2 > info.lastPreKeyId
        let lowKyber = info.nextKyberPreKeyId + 2 > info.lastKyberPreKeyId
        guard lowEC || lowKyber else { return }
        let identity = try store.identityKeyPair(context: ctx)
        let preStart = UInt32(max(info.lastPreKeyId, info.nextPreKeyId, Int(store.state.preKeyLastId), 0) + 1)
        let kyberStart = UInt32(max(info.lastKyberPreKeyId, info.nextKyberPreKeyId, Int(store.state.kyberPreKeyLastId), 0) + 1)
        var uploads = try makePreKeys(from: preStart)
        uploads += try makeKyberKeys(from: kyberStart, identity: identity)
        try await uploadAll(uploads, uid: uid, token: token)
        let ecLast = preStart + Self.batch - 1, kyLast = kyberStart + Self.batch - 1
        try check(try await api("bond/api/v3/signal/\(Self.deviceId)", "PATCH", token: token, body: [
            "registrationId": Int(store.state.registrationId),
            "lastPreKeyId": Int(ecLast), "lastKyberPreKeyId": Int(kyLast)
        ]))
        store.mutate { $0.preKeyLastId = ecLast; $0.kyberPreKeyLastId = kyLast }
    }

    private static var nowMs: UInt64 { UInt64(Date().timeIntervalSince1970 * 1000) }

    private func makePreKeys(from start: UInt32) throws -> [(String, Data)] {
        try (0..<Self.batch).map { i in
            let id = start + i
            let priv = PrivateKey.generate()
            try store.storePreKey(try PreKeyRecord(id: id, privateKey: priv), id: id, context: ctx)
            return ("preKey_\(id)", priv.publicKey.serialize())
        }
    }

    private func kyberRecord(id: UInt32, identity: IdentityKeyPair) throws -> (publicKey: Data, signature: Data) {
        let kp = KEMKeyPair.generate()
        let pub = kp.publicKey.serialize()
        let sig = identity.privateKey.generateSignature(message: pub)
        try store.storeKyberPreKey(try KyberPreKeyRecord(id: id, timestamp: Self.nowMs, keyPair: kp, signature: sig),
                                   id: id, context: ctx)
        return (pub, sig)
    }

    private func makeKyberKeys(from start: UInt32, identity: IdentityKeyPair) throws -> [(String, Data)] {
        var out: [(String, Data)] = []
        for i in 0..<Self.batch {
            let id = start + i
            let k = try kyberRecord(id: id, identity: identity)
            out.append(("kyberKey_\(id)", k.publicKey))
            out.append(("kyberKeySignature_\(id)", k.signature))
        }
        return out
    }

    private func uploadAll(_ items: [(String, Data)], uid: String, token: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (name, data) in items {
                group.addTask { try await FirebaseStorage.upload(data, to: "crypto/\(uid)/\(name)", token: token) }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Sessions

    /// Downloads a partner key file, falling back to the legacy phone-number folder.
    private func partnerFile(_ name: String, uid: String, phone: String, token: String) async throws -> Data {
        do {
            return try await FirebaseStorage.download("crypto/\(uid)/\(name)", token: token)
        } catch is FirebaseStorage.NotFound where !phone.isEmpty {
            do { return try await FirebaseStorage.download("crypto/\(phone)/\(name)", token: token) }
            catch is FirebaseStorage.NotFound { throw ChatError.partnerNotReady }
        } catch is FirebaseStorage.NotFound {
            throw ChatError.partnerNotReady
        }
    }

    /// Builds a session with the partner from their published bundle.
    func createSession(bondId: String, partnerUID: String, partnerPhone: String, token: String) async throws {
        let r = try await api("bond/api/v3/bonds/\(bondId)/signal/\(Self.deviceId)", "GET", token: token)
        if r.0 == 404 { throw ChatError.partnerNotReady }
        let info = SignalInfo((try check(r) as? [String: Any]) ?? [:])
        guard info.registrationId != -1, info.signedPreKeyId != -1 else { throw ChatError.partnerNotReady }
        guard info.nextKyberPreKeyId != -1 else { throw ChatError.partnerNeedsUpdate }

        func file(_ n: String) async throws -> Data {
            try await partnerFile(n, uid: partnerUID, phone: partnerPhone, token: token)
        }
        async let identity = file("identity_\(info.registrationId)")
        async let spk = file("signedPreKey_\(info.signedPreKeyId)")
        async let spkSig = file("signedPreKeySignature_\(info.signedPreKeyId)")
        async let kyber = file("kyberKey_\(info.nextKyberPreKeyId)")
        async let kyberSig = file("kyberKeySignature_\(info.nextKyberPreKeyId)")
        let preKey: Data? = info.nextPreKeyId >= 0 ? try await file("preKey_\(info.nextPreKeyId)") : nil

        let identityKey = try IdentityKey(bytes: try await identity)
        let bundle: PreKeyBundle
        if let preKey {
            bundle = try PreKeyBundle(
                registrationId: UInt32(info.registrationId), deviceId: Self.deviceId,
                prekeyId: UInt32(info.nextPreKeyId), prekey: try PublicKey(preKey),
                signedPrekeyId: UInt32(info.signedPreKeyId), signedPrekey: try PublicKey(try await spk),
                signedPrekeySignature: try await spkSig, identity: identityKey,
                kyberPrekeyId: UInt32(info.nextKyberPreKeyId), kyberPrekey: try KEMPublicKey(try await kyber),
                kyberPrekeySignature: try await kyberSig)
        } else {
            bundle = try PreKeyBundle(
                registrationId: UInt32(info.registrationId), deviceId: Self.deviceId,
                signedPrekeyId: UInt32(info.signedPreKeyId), signedPrekey: try PublicKey(try await spk),
                signedPrekeySignature: try await spkSig, identity: identityKey,
                kyberPrekeyId: UInt32(info.nextKyberPreKeyId), kyberPrekey: try KEMPublicKey(try await kyber),
                kyberPrekeySignature: try await kyberSig)
        }
        let addr = try address(bondId)
        do {
            try processPreKeyBundle(bundle, for: addr, sessionStore: store, identityStore: store, context: ctx)
        } catch SignalError.untrustedIdentity {
            // The partner reinstalled (new identity). Accept it, as a received message would.
            store.mutate { $0.partnerIdentities.removeValue(forKey: bondId) }
            try processPreKeyBundle(bundle, for: addr, sessionStore: store, identityStore: store, context: ctx)
        }
    }

    // MARK: - Messages

    struct Sent { let id: String; let timestamp: Date }

    /// `POST bond/api/v3/bonds/{bondId}/chatmessages {type, content}` → `{id, timestamp}`.
    private func post(bondId: String, type: Int, content: String, token: String) async throws -> Sent {
        let j = try check(try await api("bond/api/v3/bonds/\(bondId)/chatmessages", "POST", token: token,
                                        body: ["type": type, "content": content])) as? [String: Any]
        let id = ((j?["id"] as? String) ?? "").replacingOccurrences(of: "\"", with: "")
        let ms = (j?["timestamp"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
        return Sent(id: id, timestamp: Date(timeIntervalSince1970: ms / 1000))
    }

    func sendText(_ text: String, bondId: String, token: String) async throws -> Sent {
        let envelope = try encrypt(Data(text.utf8), bondId: bondId)
        return try await post(bondId: bondId, type: 1, content: Self.androidBase64(envelope), token: token)
    }

    /// Announces a new session (type 6); its ciphertext is the session's PreKeySignalMessage.
    func sendNewSession(bondId: String, token: String) async throws {
        let text = "PreKeySignalMessage::NEW_SESSION::\(Int64(Date().timeIntervalSince1970 * 1000))"
        let envelope = try encrypt(Data(text.utf8), bondId: bondId)
        _ = try await post(bondId: bondId, type: 6, content: Self.androidBase64(envelope), token: token)
    }

    /// Sends a photo: Signal-encrypted JPEG bytes uploaded to the galleries bucket, then a
    /// type 2 (shared) or 3 (secret) message whose content is the file name.
    func sendImage(_ jpeg: Data, secret: Bool, bondId: String, uid: String, token: String) async throws -> (Sent, String) {
        let envelope = try encrypt(jpeg, bondId: bondId)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss_"; f.locale = Locale(identifier: "en_US_POSIX")
        let name = f.string(from: Date()) + String(UInt64.random(in: 100_000_000...999_999_999)) + ".tmp"
        let gallery = secret ? "secret_gallery" : "shared_gallery"
        try await FirebaseStorage.upload(envelope, to: "\(gallery)/\(uid)/\(name)",
                                         bucket: FirebaseStorage.galleriesBucket, token: token)
        return (try await post(bondId: bondId, type: secret ? 3 : 2, content: name, token: token), name)
    }

    /// Downloads and decrypts a partner photo named by a type 2/3 message.
    func receiveImage(named name: String, secret: Bool, bondId: String, partnerUID: String,
                      partnerPhone: String, token: String) async throws -> Data {
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), !name.contains("..") else {
            throw SignalError.invalidMessage("bad image name")
        }
        let gallery = secret ? "secret_gallery" : "shared_gallery"
        let blob: Data
        do {
            blob = try await FirebaseStorage.download("\(gallery)/\(partnerUID)/\(name)",
                                                     bucket: FirebaseStorage.galleriesBucket, token: token)
        } catch is FirebaseStorage.NotFound where !partnerPhone.isEmpty {
            blob = try await FirebaseStorage.download("\(gallery)/\(partnerPhone)/\(name)",
                                                     bucket: FirebaseStorage.galleriesBucket, token: token)
        }
        return try decrypt(blob, bondId: bondId)
    }

    /// `GET bond/api/v3/bonds/chat` → `[{bondId, chatMessages[{id, type, content, timestamp}], info}]`.
    func sync(token: String) async throws -> [[String: Any]] {
        let j = try check(try await api("bond/api/v3/bonds/chat", "GET", token: token)) as? [String: Any]
        return (j?["chats"] as? [[String: Any]]) ?? []
    }

    func ack(bondId: String, messageId: String, token: String) async {
        _ = try? await api("bond/api/v3/bonds/\(bondId)/chatmessages/\(messageId)/acknowledge", "PUT", token: token)
    }

    func markSeen(bondId: String, messageId: String, token: String) async {
        _ = try? await api("bond/api/v3/bonds/\(bondId)/chatmessages/\(messageId)/seen", "PUT", token: token)
    }
}
