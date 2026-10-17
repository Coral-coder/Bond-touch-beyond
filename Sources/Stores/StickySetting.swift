import Foundation
import Security

/// A setting that survives app updates *and* deleting and reinstalling the app: it lives in
/// the Keychain (which iOS keeps across reinstalls), mirrored in UserDefaults.
enum StickySetting {
    private static let service = "BondTouchBeyond.sticky"

    static func bool(_ key: String, default fallback: Bool) -> Bool {
        if let data = read(key), let byte = data.first { return byte != 0 }
        if let v = UserDefaults.standard.object(forKey: "sticky.\(key)") as? Bool {
            write(key, Data([v ? 1 : 0]))   // carry an older saved value into the Keychain
            return v
        }
        return fallback
    }

    static func set(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: "sticky.\(key)")
        write(key, Data([value ? 1 : 0]))
    }

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    private static func read(_ key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func write(_ key: String, _ data: Data) {
        let q = query(key)
        // Readable after first unlock, so a background launch (a push) sees it too.
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(q as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(q.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }
}
