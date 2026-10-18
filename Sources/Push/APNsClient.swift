import CryptoKit
import Foundation

/// Sends a push notification straight from this phone to the partner's phone, through Apple's
/// APNs gateway — no server in between. When you tap, this wakes your partner's device right
/// away instead of waiting on CloudKit's silent push (which iOS throttles in deep sleep).
///
/// It is an ALERT push (a visible "… touched you" banner): only an alert is delivered with
/// high priority and reliably wakes a sleeping phone. It also carries `content-available` so,
/// when the app can run, it refreshes and drives the bracelet. If the APNs key isn't
/// configured (see APNsSecrets) every call is a no-op and the app relies on CloudKit's push.
actor APNsClient {
    static let shared = APNsClient()

    /// Apple's production gateway (TestFlight / App Store builds use production APNs).
    private let host = "https://api.push.apple.com"
    private var cachedToken: (jwt: String, madeAt: Date)?

    /// Sends an alert push to one device token. Returns true on APNs 200. Always a visible
    /// banner (phone and watch). `silent` (the partner's bracelet is connected and plays the
    /// touch itself) is kept for callers; every touch push vibrates silently either way.
    @discardableResult
    func send(toDeviceToken deviceToken: String, title: String, body: String, silent: Bool = false,
              topic: String = AppConfig.bundleID, collapseID: String? = nil,
              extra: [String: Any] = [:]) async -> Bool {
        guard APNsSecrets.isConfigured, !deviceToken.isEmpty else { return false }
        guard let jwt = currentToken() else {
            NetLog.shared.record(.fail, "APNs: couldn't sign auth token")
            return false
        }
        guard let url = URL(string: "\(host)/3/device/\(deviceToken)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue(topic, forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        if let collapseID { request.setValue(collapseID, forHTTPHeaderField: "apns-collapse-id") }

        var aps: [String: Any] = [
            "alert": ["title": title, "body": body],
            "content-available": 1,
            // Lets the receiving phone's notification extension decrypt the touch and show
            // it richly (its picture, its meaning; long press to replay it).
            "mutable-content": 1,
            // Never "passive": that files it quietly with no banner and no watch tap.
            "interruption-level": silent ? "active" : "time-sensitive",
        ]
        // A touch is felt, not heard: a sound of pure silence (bundled in the phone and watch
        // apps). iOS and watchOS only vibrate for a notification that has a sound, so this
        // makes the phone vibrate and the watch tap the wrist — with nothing to hear.
        aps["sound"] = TouchNotification.silentSound
        // App data next to "aps" (e.g. the sealed touch) — under the 4 KB push limit.
        var payload: [String: Any] = extra
        payload["aps"] = aps
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if code == 200 {
                NetLog.shared.record(.ok, "APNs: push delivered", "→ …\(deviceToken.suffix(6))")
                return true
            }
            let reason = String(data: data, encoding: .utf8) ?? ""
            NetLog.shared.record(.fail, "APNs: push rejected (\(code))", reason)
            // A stale provider token (expired/SChanged) — drop the cache so the next send re-signs.
            if code == 403 { cachedToken = nil }
            return false
        } catch {
            NetLog.shared.record(.fail, "APNs: push failed", error.localizedDescription)
            return false
        }
    }

    // MARK: - Provider token (ES256 JWT, cached ~50 min)

    private func currentToken() -> String? {
        if let c = cachedToken, Date().timeIntervalSince(c.madeAt) < 50 * 60 { return c.jwt }
        guard let jwt = Self.makeJWT(keyID: APNsSecrets.keyID, teamID: APNsSecrets.teamID,
                                     privateKeyP8: APNsSecrets.privateKeyP8) else { return nil }
        cachedToken = (jwt, Date())
        return jwt
    }

    /// Builds and signs an APNs provider JWT (header {alg:ES256, kid}, claims {iss, iat}).
    static func makeJWT(keyID: String, teamID: String, privateKeyP8: String) -> String? {
        guard let key = try? P256.Signing.PrivateKey(pemRepresentation: privateKeyP8) else { return nil }
        let header = ["alg": "ES256", "kid": keyID]
        let claims: [String: Any] = ["iss": teamID, "iat": Int(Date().timeIntervalSince1970)]
        guard let headerData = try? JSONSerialization.data(withJSONObject: header),
              let claimsData = try? JSONSerialization.data(withJSONObject: claims) else { return nil }
        let signingInput = base64url(headerData) + "." + base64url(claimsData)
        guard let signature = try? key.signature(for: Data(signingInput.utf8)) else { return nil }
        return signingInput + "." + base64url(signature.rawRepresentation)
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
