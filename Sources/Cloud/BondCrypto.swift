import CryptoKit
import Foundation

/// End-to-end encryption for a bond, keyed by the bond's secret code.
///
/// Touches, messages, location, heartbeat and profile are stored in a shared iCloud
/// database so one link connects both phones with no acceptance step — but every payload is
/// sealed with AES-GCM under a key derived from the bond code. The code only ever travels in
/// the invite link the two people exchange, so only they can decrypt. A dump of the database
/// reveals nothing without the code.
enum BondCrypto {
    /// 256-bit key derived from the bond code via HKDF-SHA256.
    static func key(forCode code: String) -> SymmetricKey {
        let material = SymmetricKey(data: Data(code.uppercased().utf8))
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: material,
                                      salt: Data("BondTouchBeyond.bond".utf8),
                                      info: Data("payload".utf8),
                                      outputByteCount: 32)
    }

    /// Seals a JSON-encodable payload for a bond. Returns nonce+ciphertext+tag combined.
    static func seal<T: Encodable>(_ value: T, code: String) -> Data? {
        guard let plaintext = try? JSONEncoder().encode(value),
              let sealed = try? AES.GCM.seal(plaintext, using: key(forCode: code)),
              let combined = sealed.combined else { return nil }
        return combined
    }

    /// Opens a sealed payload for a bond.
    static func open<T: Decodable>(_ type: T.Type, from data: Data, code: String) -> T? {
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let plaintext = try? AES.GCM.open(box, using: key(forCode: code)) else { return nil }
        return try? JSONDecoder().decode(type, from: plaintext)
    }
}
