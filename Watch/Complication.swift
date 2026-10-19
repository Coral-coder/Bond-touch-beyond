import Foundation
import Security
import WidgetKit

/// The last touch received, kept for the watch-face complication (WatchWidget/). The watch app
/// writes it whenever a partner's touch reaches the watch — from the phone (which sends it as
/// complication data, so it can wake the watch app in the background) or a notification — and
/// the complication reads it. Shared through the app's Keychain group: no App Group needed.
struct ComplicationTouch: Codable, Equatable {
    var from: String
    var pattern: [Int]
    var generation: Int
    var startRGB: Int
    var endRGB: Int
    var label: String?
    var bpm: Int?
    var at: Date

    static let kind = "BondTouchBeyondWatchLastTouch"
    private static let service = "BondTouchBeyond.complication"
    private static let account = "lastTouch"

    private static func query() -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if let group = (Bundle.main.object(forInfoDictionaryKey: "BTKeychainGroup") as? String),
           !group.isEmpty, !group.contains("$(") {
            q[kSecAttrAccessGroup as String] = group
        }
        return q
    }

    static func load() -> ComplicationTouch? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(ComplicationTouch.self, from: data)
    }

    /// Saves it (if it's newer than what's there) and refreshes the complication.
    func save() {
        if let have = Self.load(), have.at >= at { return }
        guard let data = try? JSONEncoder().encode(self) else { return }
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(Self.query() as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(Self.query().merging(attrs) { $1 } as CFDictionary, nil)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: Self.kind)
    }
}
