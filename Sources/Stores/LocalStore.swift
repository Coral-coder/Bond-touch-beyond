import Combine
import CryptoKit
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
    /// The email of the signed-in original Bond Touch account (empty if not logged in).
    @Published var legacyEmail: String {
        didSet { UserDefaults.standard.set(legacyEmail, forKey: Key.legacyEmail.rawValue) }
    }
    @Published var legacyRefreshToken: String {
        didSet { UserDefaults.standard.set(legacyRefreshToken, forKey: Key.legacyRefresh.rawValue) }
    }
    /// Per-partner home greeting ("Hello, this is us"), keyed by bond id.
    @Published var greetings: [String: String] {
        didSet { save(greetings, for: .greetings) }
    }
    /// Per-partner "next time we meet" date (the Encounters countdown), keyed by bond id.
    @Published var encounters: [String: Date] {
        didSet { save(encounters, for: .encounters) }
    }

    func nextMeeting(for bondID: String?) -> Date? {
        guard let bondID else { return nil }
        return encounters[bondID]
    }

    func setNextMeeting(_ date: Date?, for bondID: String?) {
        guard let bondID else { return }
        if let date { encounters[bondID] = date } else { encounters.removeValue(forKey: bondID) }
    }

    /// Private Space passcode, stored as a SHA-256 hash (never in the clear).
    @Published var privateSpacePasscodeHash: String? {
        didSet { UserDefaults.standard.set(privateSpacePasscodeHash, forKey: Key.psPasscode.rawValue) }
    }

    var hasPrivateSpace: Bool { privateSpacePasscodeHash != nil }

    func setPrivateSpacePasscode(_ code: String) { privateSpacePasscodeHash = Self.hash(code) }

    func checkPrivateSpacePasscode(_ code: String) -> Bool {
        guard let h = privateSpacePasscodeHash else { return false }
        return h == Self.hash(code)
    }

    private static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static let defaultGreeting = "Hello,\nthis is us"

    func greeting(for bondID: String?) -> String {
        guard let bondID, let g = greetings[bondID], !g.isEmpty else { return LocalStore.defaultGreeting }
        return g
    }

    func setGreeting(_ text: String, for bondID: String?) {
        guard let bondID else { return }
        greetings[bondID] = text
    }

    private enum Key: String { case meanings, vibration, dnd, profile, fbEnabled, fbURL, fbToken, greetings, encounters, psPasscode, legacyEmail, legacyRefresh }

    init() {
        self.meanings = LocalStore.load([TouchMeaning].self, for: .meanings) ?? TouchMeaning.starters
        let v = UserDefaults.standard.object(forKey: Key.vibration.rawValue) as? Double
        self.vibrationStrength = v ?? 200
        self.doNotDisturb = UserDefaults.standard.bool(forKey: Key.dnd.rawValue)
        self.profile = LocalStore.load(UserProfile.self, for: .profile) ?? .empty
        self.useLegacyFirebase = UserDefaults.standard.bool(forKey: Key.fbEnabled.rawValue)
        self.firebaseDatabaseURL = UserDefaults.standard.string(forKey: Key.fbURL.rawValue) ?? ""
        self.firebaseAuthToken = UserDefaults.standard.string(forKey: Key.fbToken.rawValue) ?? ""
        self.legacyEmail = UserDefaults.standard.string(forKey: Key.legacyEmail.rawValue) ?? ""
        self.legacyRefreshToken = UserDefaults.standard.string(forKey: Key.legacyRefresh.rawValue) ?? ""
        self.greetings = LocalStore.load([String: String].self, for: .greetings) ?? [:]
        self.encounters = LocalStore.load([String: Date].self, for: .encounters) ?? [:]
        self.privateSpacePasscodeHash = UserDefaults.standard.string(forKey: Key.psPasscode.rawValue)
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
