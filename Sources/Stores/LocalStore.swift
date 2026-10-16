import Combine
import Foundation

/// Small Codable-backed `UserDefaults` persistence for per-device preferences and the
/// user's saved touch meanings. (Not for relayed state — that's CloudKit.)
@MainActor
final class LocalStore: ObservableObject {
    @Published var meanings: [TouchMeaning] {
        didSet { save(meanings, for: .meanings) }
    }
    /// Default bracelet vibration strength 0–255 (mirrors the original's MotorStrength).
    @Published var vibrationStrength: Double {
        didSet { UserDefaults.standard.set(vibrationStrength, forKey: Key.vibration.rawValue) }
    }
    /// Do Not Disturb: don't buzz the bracelet for incoming touches.
    @Published var doNotDisturb: Bool {
        didSet { UserDefaults.standard.set(doNotDisturb, forKey: Key.dnd.rawValue) }
    }
    /// The local user's profile (name, colour, default pattern).
    @Published var profile: UserProfile {
        didSet { save(profile, for: .profile) }
    }
    /// Opt in to the legacy Firebase backend (experimental; see SettingsView footnote).
    @Published var useLegacyFirebase: Bool {
        didSet { UserDefaults.standard.set(useLegacyFirebase, forKey: Key.fbEnabled.rawValue) }
    }
    @Published var firebaseDatabaseURL: String {
        didSet { UserDefaults.standard.set(firebaseDatabaseURL, forKey: Key.fbURL.rawValue) }
    }
    @Published var firebaseAuthToken: String {
        didSet { UserDefaults.standard.set(firebaseAuthToken, forKey: Key.fbToken.rawValue) }
    }

    private enum Key: String { case meanings, vibration, dnd, profile, fbEnabled, fbURL, fbToken }

    init() {
        self.meanings = LocalStore.load([TouchMeaning].self, for: .meanings) ?? TouchMeaning.starters
        let v = UserDefaults.standard.object(forKey: Key.vibration.rawValue) as? Double
        self.vibrationStrength = v ?? 200
        self.doNotDisturb = UserDefaults.standard.bool(forKey: Key.dnd.rawValue)
        self.profile = LocalStore.load(UserProfile.self, for: .profile) ?? .empty
        self.useLegacyFirebase = UserDefaults.standard.bool(forKey: Key.fbEnabled.rawValue)
        self.firebaseDatabaseURL = UserDefaults.standard.string(forKey: Key.fbURL.rawValue) ?? ""
        self.firebaseAuthToken = UserDefaults.standard.string(forKey: Key.fbToken.rawValue) ?? ""
    }

    var legacyFirebase: LegacyFirebaseClient? {
        guard useLegacyFirebase, !firebaseDatabaseURL.isEmpty else { return nil }
        return LegacyFirebaseClient(databaseURL: firebaseDatabaseURL,
                                    authToken: firebaseAuthToken.isEmpty ? nil : firebaseAuthToken)
    }

    private func save<T: Encodable>(_ value: T, for key: Key) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key.rawValue)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
