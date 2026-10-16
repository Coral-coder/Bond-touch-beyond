import Foundation

/// Minimal Firebase Cloud Storage client (REST, no SDK) for the original project, used for
/// the Signal key files (`crypto/<uid>/<name>` in the default bucket) and chat photos
/// (`<shared_gallery|secret_gallery>/<uid>/<file>` in `bond-touch-galleries`). Requests are
/// authorised with the account's Firebase ID token, as the SDK does.
enum FirebaseStorage {
    static let defaultBucket = "bond-touch.appspot.com"
    static let galleriesBucket = "bond-touch-galleries"

    struct NotFound: Error {}

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
        guard code < 400 else {
            throw BondBackend.BackendError(message: "Storage HTTP \(code) for \(path): \(String(data: data, encoding: .utf8) ?? "")")
        }
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
        guard code < 400 else {
            throw BondBackend.BackendError(message: "Storage upload HTTP \(code) for \(path): \(String(data: body, encoding: .utf8) ?? "")")
        }
    }
}
