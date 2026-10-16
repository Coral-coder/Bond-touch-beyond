import Foundation

/// Minimal Firebase Cloud Storage client (REST, no SDK) for the original project, used for
/// the Signal key files (`crypto/<uid>/<name>` in the default bucket) and chat photos
/// (`<shared_gallery|secret_gallery>/<uid>/<file>` in `bond-touch-galleries`). Requests are
/// authorised with the account's Firebase ID token, as the SDK does.
enum FirebaseStorage {
    static let defaultBucket = "bond-touch.appspot.com"
    static let galleriesBucket = "bond-touch-galleries"

    struct NotFound: Error {}

    /// The project enforces Firebase App Check on Storage: only the official Bond Touch app
    /// (attested by Apple App Attest) may read or write it. This app can't, and doesn't try
    /// to get around it.
    struct AppCheckBlocked: LocalizedError {
        var errorDescription: String? {
            "The original Bond Touch servers only let the official Bond Touch app use their file storage (Firebase App Check), so encrypted chat keys and photos can't be exchanged from this app. Touches, Touch Language, greeting, encounters and presence still sync."
        }
    }

    /// Records that App Check blocked a request (shown in the debug panel).
    static var appCheckBlocked = false

    private static func failure(_ code: Int, _ body: Data, _ what: String) -> Error {
        let text = String(data: body, encoding: .utf8) ?? ""
        if (code == 401 || code == 403) && text.contains("App Check") {
            appCheckBlocked = true
            return AppCheckBlocked()
        }
        return BondBackend.BackendError(message: "Storage HTTP \(code) for \(what): \(text)")
    }

    private static func objectURL(_ bucket: String, _ path: String, media: Bool) -> URL? {
        // The object name is one path segment: every "/" must be percent-encoded.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        guard let name = path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o/\(name)" + (media ? "?alt=media" : ""))
    }

    /// Downloads an object's raw bytes. Throws `NotFound` for a missing object.
    static func download(_ path: String, bucket: String = defaultBucket, token: String) async throws -> Data {
        guard let url = objectURL(bucket, path, media: true) else { throw NotFound() }
        var req = URLRequest(url: url)
        req.setValue("Firebase " + token, forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw NotFound() }
        guard code < 400 else { throw failure(code, data, path) }
        return data
    }

    /// Uploads raw bytes to an object (overwriting it).
    static func upload(_ data: Data, to path: String, bucket: String = defaultBucket,
                       contentType: String = "application/octet-stream", token: String) async throws {
        var comps = URLComponents(string: "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o")!
        comps.queryItems = [URLQueryItem(name: "uploadType", value: "media"), URLQueryItem(name: "name", value: path)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("Firebase " + token, forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (body, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code < 400 else { throw failure(code, body, path) }
    }
}
