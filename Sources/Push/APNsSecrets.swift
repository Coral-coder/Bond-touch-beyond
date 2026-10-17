import Foundation

/// Credentials for sending a push straight to the partner's phone (see APNsClient).
///
/// These are intentionally EMPTY in the committed source so the APNs auth key never lives in
/// this public repository. The TestFlight workflow rewrites this file at build time from three
/// GitHub Actions secrets — APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_P8 — so the real key ships only
/// inside the signed app binary. When they're empty (any build without those secrets, e.g. the
/// compile check), direct push is simply dormant and the app falls back to CloudKit's own push.
enum APNsSecrets {
    /// The 10-character Key ID of an APNs auth key (Apple Developer → Keys → a key with
    /// "Apple Push Notifications service (APNs)" enabled).
    static let keyID = ""
    /// The 10-character Apple Developer Team ID.
    static let teamID = ""
    /// The contents of the downloaded AuthKey_XXXXXXXXXX.p8 (PKCS#8 PEM, including the
    /// BEGIN/END PRIVATE KEY lines).
    static let privateKeyP8 = ""

    static var isConfigured: Bool {
        !keyID.isEmpty && !teamID.isEmpty && !privateKeyP8.isEmpty
    }
}
