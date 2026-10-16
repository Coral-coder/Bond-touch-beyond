import Foundation

/// Minimal client for the original app's Firebase Realtime Database, over its REST API —
/// no Firebase SDK, no GoogleService-Info.plist required. Used only when the user opts in
/// (Settings → Legacy data) and provides a database URL (and, if the project requires it,
/// an auth token).
///
/// IMPORTANT: if the Firebase project restricts access to the original app's package name /
/// signing certificate (or App Check), requests from Beyond Touch will be rejected and
/// `testConnection()` returns `.rejected`. That's a server-side rule only the project owner
/// can change; the app can't work around it.
struct LegacyFirebaseClient {
    let databaseURL: String
    let authToken: String?

    enum Result: Equatable {
        case ok
        case rejected          // reached Firebase, but it denied us (auth / rules / App Check)
        case unreachable(String)
    }

    private func url(for path: String) -> URL? {
        var s = databaseURL
        if s.hasSuffix("/") { s.removeLast() }
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var comps = URLComponents(string: "\(s)/\(clean).json")
        if let token = authToken, !token.isEmpty {
            comps?.queryItems = [URLQueryItem(name: "auth", value: token)]
        }
        return comps?.url
    }

    /// Reads JSON at a path. Returns the decoded value, or nil if empty/denied.
    func get(_ path: String) async throws -> Any? {
        guard let url = url(for: path) else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Writes JSON at a path (PUT). No-op-safe; throws on transport errors.
    func put(_ value: Any, at path: String) async throws {
        guard let url = url(for: path) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: value)
        _ = try await URLSession.shared.data(for: req)
    }

    /// Checks whether this app can actually reach and read the database.
    func testConnection() async -> Result {
        guard let url = url(for: "/.info/serverTimeOffset") else { return .unreachable("Bad URL") }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else { return .unreachable("No response") }
            switch http.statusCode {
            case 200: return .ok
            case 401, 403: return .rejected
            default: return .unreachable("HTTP \(http.statusCode)")
            }
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }
}
