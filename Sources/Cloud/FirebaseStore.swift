import Foundation

/// The Firebase side of the relay, for bonds with Android partners (and every new bond once
/// Firebase is set up): the same opaque record names and sealed payloads as iCloud, kept in
/// Firestore through its REST API — no Firebase SDK in the app.
///
/// Collection `r`, one document per record: the sealed bytes in `p`, this install's anonymous
/// Firebase uid in `o` (only the writer may change a record), the server time in `t`. The
/// rules (in the Android repo, firestore.rules) allow reading a record by exact name, never
/// listing. Signed in anonymously; the session is kept in the Keychain-free UserDefaults since
/// it guards nothing the record names and encryption don't already.
///
/// Configured from `GoogleService-Info.plist` in the app bundle (CI writes it from the
/// GOOGLE_SERVICE_INFO_PLIST secret); without it, Firebase is off and everything stays on iCloud.
actor FirebaseStore {
    static let shared = FirebaseStore()

    struct Config { let apiKey: String; let projectID: String }

    static let config: Config? = {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let key = dict["API_KEY"] as? String, let project = dict["PROJECT_ID"] as? String,
              !key.isEmpty, !project.isEmpty else { return nil }
        return Config(apiKey: key, projectID: project)
    }()

    static var isConfigured: Bool { config != nil }

    /// A record: its sealed bytes and server time (the "change tag").
    struct Record { let payload: Data; let tag: String }

    private var idToken: String?
    private var tokenExpiry = Date.distantPast
    private(set) var uid: String?

    private var base: String {
        "https://firestore.googleapis.com/v1/projects/\(Self.config!.projectID)/databases/(default)/documents"
    }
    private func docName(_ name: String) -> String {
        "projects/\(Self.config!.projectID)/databases/(default)/documents/r/\(name)"
    }

    // MARK: Auth (anonymous)

    private func token() async throws -> String {
        if let idToken, tokenExpiry.timeIntervalSinceNow > 120 { return idToken }
        guard let config = Self.config else { throw FirebaseError.notConfigured }
        let defaults = UserDefaults.standard
        let json: [String: Any]
        if let refresh = defaults.string(forKey: "firebase.refreshToken") {
            json = try await post("https://securetoken.googleapis.com/v1/token?key=\(config.apiKey)",
                                  ["grant_type": "refresh_token", "refresh_token": refresh], auth: nil)
            idToken = json["id_token"] as? String
            uid = json["user_id"] as? String
            if let r = json["refresh_token"] as? String { defaults.set(r, forKey: "firebase.refreshToken") }
            tokenExpiry = Date().addingTimeInterval(Double(json["expires_in"] as? String ?? "3600") ?? 3600)
        } else {
            json = try await post("https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(config.apiKey)",
                                  ["returnSecureToken": true], auth: nil)
            idToken = json["idToken"] as? String
            uid = json["localId"] as? String
            if let r = json["refreshToken"] as? String { defaults.set(r, forKey: "firebase.refreshToken") }
            tokenExpiry = Date().addingTimeInterval(Double(json["expiresIn"] as? String ?? "3600") ?? 3600)
        }
        guard let idToken else { throw FirebaseError.auth }
        return idToken
    }

    // MARK: Records

    func put(_ name: String, _ payload: Data) async throws {
        let auth = try await token()
        guard let uid else { throw FirebaseError.auth }
        let body: [String: Any] = ["writes": [[
            "update": ["name": docName(name),
                       "fields": ["p": ["bytesValue": payload.base64EncodedString()], "o": ["stringValue": uid]]],
            "updateTransforms": [["fieldPath": "t", "setToServerValue": "REQUEST_TIME"]],
        ]]]
        _ = try await post("\(base):commit", body, auth: auth)
    }

    /// The records that exist among `names` (missing ones are absent).
    func get(_ names: [String]) async throws -> [String: Record] {
        guard !names.isEmpty else { return [:] }
        let auth = try await token()
        let data = try await request("\(base):batchGet", method: "POST",
                                     body: ["documents": names.map(docName)], auth: auth)
        // batchGet streams a JSON array of {found: {...}} / {missing: "..."}.
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var out: [String: Record] = [:]
        for item in items {
            guard let found = item["found"] as? [String: Any], let fullName = found["name"] as? String,
                  let fields = found["fields"] as? [String: Any],
                  let p = (fields["p"] as? [String: Any])?["bytesValue"] as? String,
                  let payload = Data(base64Encoded: p) else { continue }
            let tag = ((fields["t"] as? [String: Any])?["timestampValue"] as? String) ?? (found["updateTime"] as? String ?? "")
            out[String(fullName.split(separator: "/").last ?? "")] = Record(payload: payload, tag: tag)
        }
        return out
    }

    func delete(_ names: [String]) async {
        guard let auth = try? await token() else { return }
        for name in names {
            _ = try? await request("\(base)/r/\(name)", method: "DELETE", body: nil, auth: auth)
        }
    }

    // MARK: HTTP

    private func post(_ url: String, _ body: [String: Any], auth: String?) async throws -> [String: Any] {
        let data = try await request(url, method: "POST", body: body, auth: auth)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func request(_ url: String, method: String, body: Any?, auth: String?) async throws -> Data {
        guard let u = URL(string: url) else { throw FirebaseError.http(0, "bad URL") }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth { req.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if code == 401 || code == 403 { idToken = nil }
            throw FirebaseError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    enum FirebaseError: LocalizedError {
        case notConfigured, auth, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Firebase isn't set up in this build."
            case .auth: return "Couldn't sign in to Firebase."
            case .http(let code, let text): return "Firebase error \(code): \(text.prefix(200))"
            }
        }
    }
}
