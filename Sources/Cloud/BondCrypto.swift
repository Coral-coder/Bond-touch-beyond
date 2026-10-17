import CommonCrypto
import CryptoKit
import Foundation

/// End-to-end encryption for a bond, keyed by the bond's secret invite code.
///
/// The code only ever travels in the invite link the two people exchange — it is never
/// written to iCloud. On the phones it's stretched with PBKDF2-SHA256 (slow on purpose, so the
/// code can't be brute-forced) and split with HKDF into two independent values:
///   • the AES-GCM key every payload is sealed with, and
///   • an opaque **locator** used to name the bond's records in iCloud.
/// Knowing a locator (e.g. from a record name) reveals nothing about the code or the key, so
/// the database holds only meaningless IDs and ciphertext — readable by no one but the two
/// people with the link.
enum BondCrypto {
    private struct Secrets { let key: SymmetricKey; let locator: String }
    private static var cache: [String: Secrets] = [:]
    private static let lock = NSLock()

    /// The opaque ID that names this bond's records in iCloud (32 hex chars).
    static func locator(forCode code: String) -> String { secrets(code).locator }

    /// Seals a JSON-encodable payload for a bond. Returns nonce+ciphertext+tag combined.
    static func seal<T: Encodable>(_ value: T, code: String) -> Data? {
        guard let plaintext = try? JSONEncoder().encode(value),
              let sealed = try? AES.GCM.seal(plaintext, using: secrets(code).key),
              let combined = sealed.combined else { return nil }
        return combined
    }

    /// Opens a sealed payload for a bond.
    static func open<T: Decodable>(_ type: T.Type, from data: Data, code: String) -> T? {
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let plaintext = try? AES.GCM.open(box, using: secrets(code).key) else { return nil }
        return try? JSONDecoder().decode(type, from: plaintext)
    }

    // MARK: - Derivation (cached per code; the stretch takes ~0.1 s)

    private static func secrets(_ rawCode: String) -> Secrets {
        let code = rawCode.uppercased()
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[code] { return cached }
        let master = SymmetricKey(data: pbkdf2(Data(code.utf8), salt: Data("BondTouchBeyond.bond.v2".utf8)))
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: Data(),
                                         info: Data("payload".utf8), outputByteCount: 32)
        let locatorKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: Data(),
                                                info: Data("locator".utf8), outputByteCount: 16)
        let locator = locatorKey.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
        let secrets = Secrets(key: key, locator: locator)
        cache[code] = secrets
        return secrets
    }

    private static func pbkdf2(_ password: Data, salt: Data, rounds: UInt32 = 210_000) -> Data {
        var derived = Data(count: 32)
        _ = derived.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int32 in
            password.withUnsafeBytes { (pw: UnsafeRawBufferPointer) -> Int32 in
                salt.withUnsafeBytes { (s: UnsafeRawBufferPointer) -> Int32 in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         pw.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                                         s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                         out.baseAddress?.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        return derived
    }
}
