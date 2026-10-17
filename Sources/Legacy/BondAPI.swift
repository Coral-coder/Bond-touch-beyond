import Foundation

/// Typed calls to the original Bond API, matching the Android app's Retrofit interface and
/// request/response bodies (decompiled v11.2.0). Responses are parsed leniently with
/// `JSONSerialization` so a missing or extra field never breaks a sync.
///
/// Wire facts used here:
/// - `GET bond/api/v4/bonds` → `{bonds: [Bond]}`; a Bond carries `bondId`, `email`,
///   `firebaseId`, `status` (REQUESTED / BONDED / RECEIVED / NONE), `profile {name, color}`,
///   `settings {color, icon}`, `touches [{id, meaning, message {timestamp, pattern, generation}}]`,
///   `meanings [...]`, `dashboardMessage`, `encounterDateTimestamp`.
/// - A touch `pattern` is the on/off millisecond list; `generation` is "2" or "3" ("3" only
///   for the BTM / third-generation bracelet).
/// - Colours are Android ARGB ints.
extension BondBackend {

    // MARK: - Session refresh

    /// Exchanges the refresh token for a fresh ID token (Firebase ID tokens last one hour).
    static func refreshSession(refreshToken: String) async throws -> Session {
        var req = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=" + apiKey)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(iosBundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"),
                           URLQueryItem(name: "refresh_token", value: refreshToken)]
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let j = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = ((j["error"] as? [String: Any])?["message"] as? String) ?? "Token refresh failed (\(http.statusCode))"
            throw BackendError(message: msg)
        }
        guard let id = j["id_token"] as? String, let refresh = j["refresh_token"] as? String else {
            throw BackendError(message: "Token refresh returned no token")
        }
        return Session(idToken: id, refreshToken: refresh, uid: (j["user_id"] as? String) ?? "")
    }

    /// The `exp` claim of a Firebase ID token.
    static func tokenExpiry(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let exp = (j["exp"] as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// The Firebase UID (`user_id` / `sub` claim) of an ID token.
    static func tokenUID(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (j["user_id"] as? String) ?? (j["sub"] as? String)
    }

    // MARK: - JSON helpers

    private static func call(_ path: String, _ method: String, bearer: String,
                             body: [String: Any]? = nil) async throws -> Any? {
        let data = try await bond(path, method: method, bearer: bearer, body: body)
        return data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
    }

    /// Android ARGB int → 0xRRGGBB.
    static func rgb(fromAndroid value: Any?) -> Int? {
        guard let n = value as? NSNumber else { return nil }
        return Int(truncatingIfNeeded: n.int64Value) & 0xFFFFFF
    }

    /// 0xRRGGBB → opaque Android ARGB int (signed 32-bit, as Android stores it).
    static func androidColor(fromRGB rgb: Int) -> Int {
        Int(Int32(bitPattern: 0xFF00_0000 | UInt32(rgb & 0xFFFFFF)))
    }

    /// `generation` serialises as "2" / "3" (or a number); anything else is 2.
    static func generation(_ value: Any?) -> Int {
        if let s = value as? String { return s == "3" ? 3 : 2 }
        return (value as? NSNumber)?.intValue == 3 ? 3 : 2
    }

    static func pattern(_ value: Any?) -> [Int] {
        ((value as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.intValue }
    }

    // MARK: - Bonds

    /// `GET bond/api/v4/bonds` — every bond (partners, sent and received invites).
    static func getBonds(bearer: String) async throws -> [[String: Any]] {
        let j = try await call("bond/api/v4/bonds", "GET", bearer: bearer) as? [String: Any]
        return (j?["bonds"] as? [[String: Any]]) ?? []
    }

    /// `GET bond/api/v3/bonds/details` — per-partner location, battery and sharing flag.
    static func getPartnersDetails(bearer: String) async throws -> [[String: Any]] {
        (try await call("bond/api/v3/bonds/details", "GET", bearer: bearer) as? [[String: Any]]) ?? []
    }

    /// `POST bond/api/v4/bonds {email}` — invite someone by their account email.
    static func createBond(email: String, bearer: String) async throws {
        _ = try await call("bond/api/v4/bonds", "POST", bearer: bearer, body: ["email": email])
    }

    /// `POST bond/api/v4/bonds/{id}/accept`.
    static func acceptBond(_ id: String, bearer: String) async throws {
        _ = try await call("bond/api/v4/bonds/\(id)/accept", "POST", bearer: bearer)
    }

    /// `DELETE bond/api/v3/bonds/{id}` — unbond, cancel a sent invite or decline a received one.
    static func cancelBond(_ id: String, bearer: String) async throws {
        _ = try await call("bond/api/v3/bonds/\(id)", "DELETE", bearer: bearer)
    }

    /// `PUT bond/api/v3/bonds/{id}/settings {color, icon}` — your colour for this partner.
    static func updatePartnerSettings(_ id: String, colorRGB: Int, icon: String, bearer: String) async throws {
        _ = try await call("bond/api/v3/bonds/\(id)/settings", "PUT", bearer: bearer,
                           body: ["color": androidColor(fromRGB: colorRGB), "icon": icon])
    }

    /// `PUT bond/api/v3/bonds/{id}/message {message}` — the dashboard greeting.
    static func updatePartnerMessage(_ id: String, message: String, bearer: String) async throws {
        _ = try await call("bond/api/v3/bonds/\(id)/message", "PUT", bearer: bearer, body: ["message": message])
    }

    /// `PUT bond/api/v3/bonds/{id}/encounter {timestamp}` — next encounter, in Unix SECONDS
    /// (the original sends `date.getTime() / 1000`); 0 clears.
    static func updateEncounter(_ id: String, date: Date?, bearer: String) async throws {
        let seconds = date.map { Int64($0.timeIntervalSince1970) } ?? 0
        _ = try await call("bond/api/v3/bonds/\(id)/encounter", "PUT", bearer: bearer, body: ["timestamp": seconds])
    }

    /// `encounterDateTimestamp` from a bond (Unix seconds). Earlier builds of this app wrote
    /// milliseconds by mistake; a value that large is read as milliseconds and flagged so it
    /// can be rewritten correctly.
    static func encounterDate(fromTimestamp value: Double) -> (date: Date?, wrongUnits: Bool) {
        guard value > 0 else { return (nil, false) }
        if value > 100_000_000_000 { return (Date(timeIntervalSince1970: value / 1000), true) }
        return (Date(timeIntervalSince1970: value), false)
    }

    // MARK: - Touches

    /// `POST bond/api/v3/bonds/{bondId}/touches {timestamp, pattern, generation}` → touch id.
    /// Generation 3 patterns are position samples (≤ 200); generation 2 on/off ms.
    @discardableResult
    /// Returns the new touch's id and — as the original app reads it — the id of the saved
    /// meaning the server matched the pattern to, if any.
    @discardableResult
    static func sendTouch(bondId: String, pattern: [Int], generation: Int,
                          bearer: String) async throws -> (id: String?, meaningID: String?) {
        let body: [String: Any] = [
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "pattern": generation == 3 ? Array(TouchPattern.trimmed(pattern)) : (pattern.isEmpty ? [200] : pattern),
            "generation": generation == 3 ? "3" : "2"
        ]
        let j = try await call("bond/api/v3/bonds/\(bondId)/touches", "POST", bearer: bearer, body: body) as? [String: Any]
        return (j?["id"] as? String, meaningRef(j?["meaning"]))
    }

    /// A touch's `meaning` reference — a meaning id, sent as a string or a number.
    static func meaningRef(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    /// `POST bond/api/v3/bonds/{bondId}/touches/basic {timestamp, meaningId}` — sends a saved
    /// meaning by its id, so the partner's app plays it as that meaning (its colour lights
    /// their bracelet). The original app uses this for Touch Language sends, not the raw
    /// pattern endpoint.
    @discardableResult
    static func sendMeaningTouch(bondId: String, meaningId: String, bearer: String) async throws -> String? {
        let body: [String: Any] = [
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "meaningId": meaningId
        ]
        let j = try await call("bond/api/v3/bonds/\(bondId)/touches/basic", "POST", bearer: bearer, body: body)
        return (j as? [String: Any])?["id"] as? String
    }

    /// `PUT bond/api/v3/bonds/{bondId}/touches/{id}/acknowledge`.
    static func ackTouch(bondId: String, touchId: String, bearer: String) async throws {
        _ = try await call("bond/api/v3/bonds/\(bondId)/touches/\(touchId)/acknowledge", "PUT", bearer: bearer)
    }

    // MARK: - Touch meanings

    private static func meaningBody(_ m: TouchMeaning) -> [String: Any] {
        [
            "name": m.label,
            "pattern": m.touchGeneration == 3 ? TouchPattern.trimmed(m.pattern) : (m.pattern.isEmpty ? [200] : m.pattern),
            "startColor": androidColor(fromRGB: m.colorRGB),
            "endColor": androidColor(fromRGB: m.endColorRGB),
            "generation": m.touchGeneration == 3 ? "3" : "2",
            "favourite": false
        ]
    }

    /// `POST bond/api/v3/bonds/{bondId}/meanings` → the created meaning's server id.
    static func createMeaning(bondId: String, _ m: TouchMeaning, bearer: String) async throws -> String? {
        let j = try await call("bond/api/v3/bonds/\(bondId)/meanings", "POST", bearer: bearer,
                               body: meaningBody(m))
        return (j as? [String: Any])?["id"] as? String
    }

    /// `PUT bond/api/v3/bonds/{bondId}/meanings/{meaningId}`.
    static func updateMeaning(bondId: String, meaningId: String, _ m: TouchMeaning,
                              bearer: String) async throws {
        _ = try await call("bond/api/v3/bonds/\(bondId)/meanings/\(meaningId)", "PUT", bearer: bearer,
                           body: meaningBody(m))
    }

    /// `DELETE bond/api/v3/bonds/{bondId}/meanings/{meaningId}`.
    static func deleteMeaning(bondId: String, meaningId: String, bearer: String) async throws {
        _ = try await call("bond/api/v3/bonds/\(bondId)/meanings/\(meaningId)", "DELETE", bearer: bearer)
    }

    /// Parses a server meaning (`MeaningDto`) into the app's model.
    static func meaning(from j: [String: Any]) -> TouchMeaning? {
        guard let id = j["id"] as? String else { return nil }
        let start = rgb(fromAndroid: j["startColor"]) ?? 0xFF2E74
        return TouchMeaning(label: (j["name"] as? String) ?? "Touch", emoji: "",
                            colorRGB: start, endColorRGB: rgb(fromAndroid: j["endColor"]) ?? start,
                            pattern: pattern(j["pattern"]), serverID: id,
                            generation: generation(j["generation"]))
    }

    // MARK: - User / presence

    /// `PUT bond/api/v3/user/status {online}` → `{partners: [{bondId, online}]}`.
    static func setOnline(_ online: Bool, bearer: String) async throws -> [String: Bool] {
        let j = try await call("bond/api/v3/user/status", "PUT", bearer: bearer, body: ["online": online])
        var out: [String: Bool] = [:]
        for p in ((j as? [String: Any])?["partners"] as? [[String: Any]]) ?? [] {
            if let id = p["bondId"] as? String { out[id] = (p["online"] as? Bool) ?? false }
        }
        return out
    }

    /// `PUT bond/api/v3/user/details/location {lat, lng, timezone}`.
    static func updateLocation(lat: Double, lng: Double, bearer: String) async throws {
        _ = try await call("bond/api/v3/user/details/location", "PUT", bearer: bearer,
                           body: ["lat": lat, "lng": lng, "timezone": TimeZone.current.identifier])
    }

    /// `PUT bond/api/v3/user/details/sharing {sharing}`.
    static func updateSharing(_ sharing: Bool, bearer: String) async throws {
        _ = try await call("bond/api/v3/user/details/sharing", "PUT", bearer: bearer, body: ["sharing": sharing])
    }

    /// Updates the account's profile name and colour: `GET bond/api/v3/user`, change
    /// `profile.name` / `profile.color`, bump `profile.version`, `PUT bond/api/v3/user`.
    static func updateProfile(name: String, colorRGB: Int, bearer: String) async throws {
        guard var user = try await call("bond/api/v3/user", "GET", bearer: bearer) as? [String: Any] else { return }
        var profile = (user["profile"] as? [String: Any]) ?? [:]
        profile["name"] = name
        profile["color"] = androidColor(fromRGB: colorRGB)
        profile["version"] = ((profile["version"] as? NSNumber)?.int64Value ?? 0) + 1
        user["profile"] = profile
        user.removeValue(forKey: "bypassFlags")   // not part of the update body
        _ = try await call("bond/api/v3/user", "PUT", bearer: bearer, body: user)
    }

    /// Marks the profile as having (or not having) a photo and bumps its version, as the
    /// original app does after uploading `images/<uid>/profile`. Only call after the upload
    /// succeeded, or the official app would show a broken photo.
    static func setProfileHasImage(_ hasImage: Bool, bearer: String) async throws {
        guard var user = try await call("bond/api/v3/user", "GET", bearer: bearer) as? [String: Any] else { return }
        var profile = (user["profile"] as? [String: Any]) ?? [:]
        profile["hasImage"] = hasImage
        profile["version"] = ((profile["version"] as? NSNumber)?.int64Value ?? 0) + 1
        user["profile"] = profile
        user.removeValue(forKey: "bypassFlags")
        _ = try await call("bond/api/v3/user", "PUT", bearer: bearer, body: user)
    }
}
