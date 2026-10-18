import Foundation
import Security

/// The iCloud bond codes, shared through the Keychain with the notification extensions, so
/// a partner's push can be decrypted on this phone and shown as a rich notification (the
/// touch drawn, its meaning). The codes never leave the phone; the Keychain group is this
/// app's own (`BTKeychainGroup` in Info.plist: <team>.<bundle id>.shared).
enum SharedBonds {
    private static let service = "BondTouchBeyond.bonds"
    private static let account = "codes"

    private static var group: String? {
        (Bundle.main.object(forInfoDictionaryKey: "BTKeychainGroup") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func query() -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    /// The app saves every iCloud bond code here whenever its bonds change.
    static func save(_ codes: [String]) {
        guard let data = try? JSONEncoder().encode(codes.sorted()) else { return }
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    // Readable once the phone has been unlocked since restart,
                                    // so a push on a locked phone can still be decrypted.
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(query() as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query().merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    static func codes() -> [String] {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
