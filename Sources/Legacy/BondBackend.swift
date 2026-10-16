import Foundation

/// Client for the original Bond Touch backend — Firebase Auth (project `bond-touch`) plus
/// `api.bond-touch.com` — used as a bridge so you can sign in with your existing account
/// until the CloudKit move is complete.
///
/// Reverse-engineered from the app's `request-pin` / `validate-pin` flow:
///  1. sign in to Firebase anonymously to get a bearer token and a uid (`firebaseId`),
///  2. `POST bond/api/v3/auth/request-pin {email}` — the backend emails a 6-digit PIN,
///  3. `POST bond/api/v3/auth/validate-pin {email, firebaseId, pin}` → `{token}` (a Firebase
///     custom token),
///  4. `signInWithCustomToken` → the real account's ID token,
///  5. call the Bond API (`bond/api/v3/user`, …) with `Authorization: Bearer <idToken>`.
///
/// The Firebase API key is restricted to the original Android app, so the identity requests
/// send that app's `X-Android-Package` / `X-Android-Cert` identity, exactly as the app does.
enum BondBackend {
    static let apiKey = "AIzaSyAdRp2UpcN345BkLVEIt6VjnIZS1ysEsL0"
    static let apiBase = URL(string: "https://api.bond-touch.com/")!
    static let androidPackage = "com.impossible.bondtouch"
    static let androidCert = "23460F11B7C87B163329E7ECF3B6D6D89A139E33"
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
        req.setValue(androidPackage, forHTTPHeaderField: "X-Android-Package")
        req.setValue(androidCert, forHTTPHeaderField: "X-Android-Cert")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "Auth failed (\(http.statusCode))"
            throw BackendError(message: msg)
        }
        return json
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
    private static func bond(_ path: String, method: String = "POST", bearer: String,
                             body: [String: Any]? = nil) async throws -> Data {
        var req = URLRequest(url: apiBase.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw BackendError(message: "Request to \(path) failed (\(http.statusCode))")
        }
        return data
    }

    static func requestPin(email: String, bearer: String) async throws {
        try await bond("bond/api/v3/auth/request-pin", bearer: bearer, body: ["email": email])
    }

    static func validatePin(email: String, firebaseId: String, pin: String, bearer: String) async throws -> String {
        let data = try await bond("bond/api/v3/auth/validate-pin", bearer: bearer,
                                  body: ["email": email, "firebaseId": firebaseId, "pin": pin])
        let j = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        guard let token = j["token"] as? String else { throw BackendError(message: "No custom token returned") }
        return token
    }

    static func currentUserEmail(bearer: String) async throws -> String {
        let data = try await bond("bond/api/v3/user", method: "GET", bearer: bearer)
        let j = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        return (j["email"] as? String) ?? ""
    }

    // MARK: - Two-step login

    /// Step 1: anonymous sign-in, then email a PIN. Returns the anonymous session whose
    /// bearer/uid are needed to validate the PIN.
    static func beginEmailLogin(email: String) async throws -> Session {
        let anon = try await anonymousSignIn()
        try await requestPin(email: email, bearer: anon.idToken)
        return anon
    }

    /// Step 2: validate the PIN and upgrade to the real account session.
    static func completeEmailLogin(email: String, pin: String, anon: Session) async throws -> Session {
        let customToken = try await validatePin(email: email, firebaseId: anon.uid, pin: pin, bearer: anon.idToken)
        return try await signIn(customToken: customToken)
    }
}
