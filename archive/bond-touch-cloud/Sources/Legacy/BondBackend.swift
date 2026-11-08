import Foundation

/// Client for the original Bond Touch backend — Firebase Auth (project `bond-touch`) plus
/// `api.bond-touch.com` — used as a bridge so you can sign in with your existing account
/// until the CloudKit move is complete.
///
/// Auth matches the real iOS app (recovered from the IPA: Firebase Email Link sign-in):
///  1. `POST accounts:sendOobCode {requestType: EMAIL_SIGNIN, email, continueUrl}` — Firebase
///     emails a sign-in link; the user opens it and pastes the link back,
///  2. `POST accounts:signInWithEmailLink {email, oobCode}` → the account's ID token,
///  3. call the Bond API (`bond/api/v3/user`, …) with `Authorization: Bearer <idToken>`.
///
/// The Firebase key is the iOS key, authorised with the `X-Ios-Bundle-Identifier` header
/// (`com.impossible.bondtouch`) — the same identity the iOS app presents.
enum BondBackend {
    // iOS Firebase config (from the real iOS app's GoogleService-Info.plist). The iOS app
    // authenticates with Firebase Email Link sign-in, authorising the key with the iOS
    // bundle-identifier header (not the Android package/cert).
    static let apiKey = "AIzaSyBKWjCliQP5HvvM6QtTQfFaGTvD27847_c"
    static let iosBundleId = "com.impossible.bondtouch"
    static let apiBase = URL(string: "https://api.bond-touch.com/")!
    static let projectId = "bond-touch"
    static let rtdbURL = "https://bond-touch.firebaseio.com"
    static let storageBucket = "bond-touch.appspot.com"
    static let senderId = "625752440215"
    /// Where the email-link lands; the oobCode is read from the link the user pastes back.
    static let continueURL = "https://bond-touch.firebaseapp.com/"
    private static let identityBase = "https://identitytoolkit.googleapis.com/v1/"

    struct Session: Equatable {
        let idToken: String
        let refreshToken: String
        let uid: String
    }

    struct BackendError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Firebase identitytoolkit

    private static func identity(_ method: String, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: identityBase + method + "?key=" + apiKey)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(iosBundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "Auth failed (\(http.statusCode))"
            throw BackendError(message: msg)
        }
        return json
    }

    // MARK: - Firebase Email Link sign-in (the real iOS flow)

    /// Sends a Firebase email sign-in link to `email` (identitytoolkit `sendOobCode`,
    /// requestType EMAIL_SIGNIN). The user opens the email and pastes the link back.
    static func sendEmailSignInLink(email: String) async throws {
        _ = try await identity("accounts:sendOobCode", body: [
            "requestType": "EMAIL_SIGNIN",
            "email": email,
            "continueUrl": continueURL,
            "canHandleCodeInApp": true
        ])
    }

    /// Completes email-link sign-in with the `oobCode` extracted from the pasted link.
    static func signInWithEmailLink(email: String, oobCode: String) async throws -> Session {
        try session(from: try await identity("accounts:signInWithEmailLink",
                                             body: ["email": email, "oobCode": oobCode]))
    }

    /// Pulls the Firebase oobCode out of a pasted sign-in link (handles plain and
    /// Dynamic-Link–wrapped URLs).
    static func oobCode(fromLink link: String) -> String? {
        guard let comps = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        if let code = comps.queryItems?.first(where: { $0.name == "oobCode" })?.value { return code }
        // Dynamic Link wraps the real URL in a `link=` query item.
        if let inner = comps.queryItems?.first(where: { $0.name == "link" })?.value,
           let innerComps = URLComponents(string: inner) {
            return innerComps.queryItems?.first(where: { $0.name == "oobCode" })?.value
        }
        return nil
    }

    private static func session(from j: [String: Any]) throws -> Session {
        guard let idToken = j["idToken"] as? String, let refresh = j["refreshToken"] as? String else {
            throw BackendError(message: "No token in response")
        }
        let uid = (j["localId"] as? String) ?? (j["user_id"] as? String) ?? ""
        return Session(idToken: idToken, refreshToken: refresh, uid: uid)
    }

    static func anonymousSignIn() async throws -> Session {
        try session(from: try await identity("accounts:signUp", body: ["returnSecureToken": true]))
    }

    static func signIn(customToken: String) async throws -> Session {
        try session(from: try await identity("accounts:signInWithCustomToken",
                                             body: ["token": customToken, "returnSecureToken": true]))
    }

    // MARK: - Bond API

    @discardableResult
    static func bond(_ path: String, method: String = "POST", bearer: String?,
                             body: [String: Any]? = nil) async throws -> Data {
        var req = URLRequest(url: apiBase.appendingPathComponent(path))
        req.httpMethod = method
        if let bearer { req.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        // Touch sends are the ones worth tracing; log their result to the debug panel.
        let isTouch = path.contains("/touches")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code >= 400 {
                let detail = String(data: data, encoding: .utf8) ?? ""
                if isTouch { NetLog.shared.record(.fail, "Touch → Bond API \(method) /\(path)", "HTTP \(code): \(detail)") }
                throw BackendError(message: "HTTP \(code) at /\(path): \(detail)")
            }
            if isTouch { NetLog.shared.record(.ok, "Touch → Bond API \(method) /\(path)", "HTTP \(code) OK") }
            return data
        } catch let error as BackendError {
            throw error
        } catch {
            if isTouch { NetLog.shared.record(.fail, "Touch → Bond API \(method) /\(path)", error.localizedDescription) }
            throw error
        }
    }

    static func requestPin(email: String, bearer: String? = nil) async throws {
        try await bond("bond/api/v3/auth/request-pin", bearer: bearer, body: ["email": email])
    }

    static func validatePin(email: String, firebaseId: String, pin: String, bearer: String? = nil) async throws -> String {
        let data = try await bond("bond/api/v3/auth/validate-pin", bearer: bearer,
                                  body: ["email": email, "firebaseId": firebaseId, "pin": pin])
        let j = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        guard let token = j["token"] as? String else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw BackendError(message: "No custom token returned. Response: \(detail)")
        }
        return token
    }

    static func currentUserEmail(bearer: String) async throws -> String {
        let data = try await bond("bond/api/v3/user", method: "GET", bearer: bearer)
        let j = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        return (j["email"] as? String) ?? ""
    }

    // MARK: - Raw data dump (debug)

    /// A single GET, returning the HTTP status plus the pretty-printed JSON (or raw body).
    static func rawGet(_ path: String, bearer: String) async -> String {
        var req = URLRequest(url: apiBase.appendingPathComponent(path))
        req.httpMethod = "GET"
        req.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return "HTTP \(code)\n" + pretty(data)
        } catch {
            return "ERROR: \(error.localizedDescription)"
        }
    }

    private static func pretty(_ data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: out, encoding: .utf8) {
            return s
        }
        return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
    }

    /// Account-level GET endpoints (no path parameters).
    static let accountReadPaths = [
        "bond/api/v4/bonds",
        "bond/api/v3/user",
        "bond/api/v3/user/details",
        "bond/api/v3/user/status",
        "bond/api/v3/user/consent",
        "bond/api/v3/meanings/recommendations",
        "bond/api/v3/bonds/details",
        "bond/api/v3/bonds/chat"
    ]

    private static func bondIds(bearer: String) async -> [String] {
        var req = URLRequest(url: apiBase.appendingPathComponent("bond/api/v4/bonds"))
        req.httpMethod = "GET"
        req.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        var ids: [String] = []
        func scan(_ any: Any) {
            if let arr = any as? [Any] { arr.forEach(scan) }
            else if let obj = any as? [String: Any] {
                if let b = obj["bondId"] as? String { ids.append(b) }
                else if let b = obj["id"] as? String { ids.append(b) }
                obj.values.forEach(scan)
            }
        }
        if let json = try? JSONSerialization.jsonObject(with: data) { scan(json) }
        return Array(Set(ids))
    }

    /// One endpoint's fetched result for the tree viewer / editor.
    struct Fetched: Identifiable {
        let id = UUID()
        let path: String
        let status: Int
        let pretty: String
        let json: Any?
        /// True when the endpoint has a matching write (PUT) so it can be edited back.
        let editable: Bool
    }

    private static func fetchOne(_ path: String, bearer: String, editable: Bool) async -> Fetched {
        var req = URLRequest(url: apiBase.appendingPathComponent(path))
        req.httpMethod = "GET"
        req.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return Fetched(path: path, status: code, pretty: pretty(data),
                           json: try? JSONSerialization.jsonObject(with: data), editable: editable)
        } catch {
            return Fetched(path: path, status: -1, pretty: "ERROR: \(error.localizedDescription)",
                           json: nil, editable: false)
        }
    }

    /// Account-level endpoints that accept a PUT of the same body (so they're editable).
    private static let editablePaths: Set<String> = [
        "bond/api/v3/user", "bond/api/v3/user/details"
    ]

    /// Structured dump for the tree viewer: each account endpoint, then each bond's data.
    static func dumpAccountStructured(bearer: String) async -> [Fetched] {
        var out: [Fetched] = []
        for path in accountReadPaths {
            out.append(await fetchOne(path, bearer: bearer, editable: editablePaths.contains(path)))
        }
        for id in await bondIds(bearer: bearer) {
            for path in ["bond/api/v3/bonds/\(id)/meanings",
                         "bond/api/v3/bonds/\(id)/chatmessages",
                         "bond/api/v3/presences/\(id)",
                         "bond/api/v3/presences/\(id)/places"] {
                out.append(await fetchOne(path, bearer: bearer, editable: false))
            }
        }
        return out
    }

    /// Writes an edited body back to an endpoint with PUT; returns the status + response.
    static func putRaw(_ path: String, body: Data, bearer: String) async -> String {
        var req = URLRequest(url: apiBase.appendingPathComponent(path))
        req.httpMethod = "PUT"
        req.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return "HTTP \(code)\n" + pretty(data)
        } catch {
            return "ERROR: \(error.localizedDescription)"
        }
    }

    /// Dumps everything the signed-in account can read: every account endpoint, then each
    /// bond's meanings, chat messages, presence and places.
    static func dumpAccount(bearer: String) async -> String {
        var out = ""
        func dump(_ path: String) async {
            out += "━━━━━━ GET /\(path) ━━━━━━\n" + (await rawGet(path, bearer: bearer)) + "\n\n"
        }
        for path in accountReadPaths { await dump(path) }
        for id in await bondIds(bearer: bearer) {
            for path in ["bond/api/v3/bonds/\(id)/meanings",
                         "bond/api/v3/bonds/\(id)/chatmessages",
                         "bond/api/v3/presences/\(id)",
                         "bond/api/v3/presences/\(id)/places"] {
                await dump(path)
            }
        }
        return out.isEmpty ? "Nothing returned." : out
    }

    // MARK: - Two-step login

    /// Step 1: send the Firebase email sign-in link (the real iOS flow).
    static func beginEmailLogin(email: String) async throws {
        try await sendEmailSignInLink(email: email)
    }

    /// Step 2: the user pastes the link from the email; sign in with its oobCode.
    static func completeEmailLogin(email: String, link: String) async throws -> Session {
        guard let code = oobCode(fromLink: link) else {
            throw BackendError(message: "Couldn't find the sign-in code in that link. Paste the whole link from the email.")
        }
        return try await signInWithEmailLink(email: email, oobCode: code)
    }
}
