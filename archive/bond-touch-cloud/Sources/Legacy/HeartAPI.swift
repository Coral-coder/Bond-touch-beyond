import Foundation

/// The original Bond Heart REST API (`https://api.bond-touch.com/heart/api/v2/…`), with the
/// same Firebase bearer token as the Bond API. Paths, methods and bodies are from the
/// decompiled Android app's `HeartApiService` and request/response classes (Gson field
/// names, so the JSON keys are the Kotlin property names):
///
/// - `GET  user/heartbeats` → `{heartbeats: [HeartbeatItemDto], pendingHeartbeats: [PendingHeartbeatItemDto]}`
/// - `POST user/heartbeats` `{pattern, name, color, isSelf:false, createdDate, hasMemory, emails}` → item
/// - `PUT  user/heartbeats/{id}` `{name, color, hasMemory, emails}` → item (edit)
/// - `PUT  user/heartbeats/{id}` (no body) → item — accepts a pending heartbeat
/// - `DELETE user/heartbeats/{id}` — delete one (and reject a pending one)
/// - `PUT  heartbeats/{id}/requests` `{toUserEmail, message, notify}` — share a heartbeat by email
/// - `GET  requests` → `[RequestDto {id, fromUser, fromUserName, toUser, createdDate}]`
/// - `POST requests` `{fromUserName, toUser}` → RequestDto — ask someone for their heartbeat
/// - `DELETE requests/{id}`
/// - `POST user/heartbeats/{id}/count` `{name, count, sinceDate "yyyy-MM-dd", controlTimestamp}` → `{controlTimestamp}`
/// - `POST user/heartbeats/{id}/total_count` `{count, name}`
///
/// Colours go up as 0xRRGGBB (`color & 0xFFFFFF`, as the original). `createdDate` is epoch
/// milliseconds (the original sends `Instant.toEpochMilli()`); seconds are accepted on read.
enum HeartAPI {
    private static func call(_ path: String, _ method: String, bearer: String,
                             body: [String: Any]? = nil) async throws -> Any? {
        let data = try await BondBackend.bond("heart/api/v2/" + path, method: method, bearer: bearer, body: body)
        return data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
    }

    private static func date(_ v: Any?) -> Date {
        guard let n = (v as? NSNumber)?.doubleValue, n > 0 else { return Date() }
        return Date(timeIntervalSince1970: n > 100_000_000_000 ? n / 1000 : n)
    }

    private static func color(_ v: Any?) -> Int {
        Int(truncatingIfNeeded: (v as? NSNumber)?.int64Value ?? Int64(EKG.colorRGB)) & 0xFFFFFF
    }

    private static func string(_ v: Any?) -> String { (v as? String) ?? "" }

    /// A server heartbeat (HeartbeatItemDto).
    struct Item {
        let id: String
        let name: String
        let colorRGB: Int
        let intervals: [Int]
        let createdAt: Date
        let createdBy: String
        let hasMemory: Bool
        let isSelf: Bool
        let emails: [String]
    }

    private static func item(_ j: [String: Any]) -> Item? {
        guard let id = j["id"] as? String else { return nil }
        return Item(id: id, name: string(j["name"]), colorRGB: color(j["color"]),
                    intervals: BondBackend.pattern(j["pattern"]), createdAt: date(j["createdDate"]),
                    createdBy: string(j["createdBy"]), hasMemory: (j["hasMemory"] as? Bool) ?? false,
                    isSelf: (j["isSelf"] as? Bool) ?? false, emails: (j["emails"] as? [String]) ?? [])
    }

    private static func pending(_ j: [String: Any]) -> PendingHeartbeat? {
        guard let id = j["id"] as? String else { return nil }
        return PendingHeartbeat(id: id, name: string(j["name"]), colorRGB: color(j["color"]),
                                createdBy: string(j["createdBy"]), createdAt: date(j["createdDate"]),
                                message: string(j["message"]), intervals: BondBackend.pattern(j["pattern"]))
    }

    private static func request(_ j: [String: Any]) -> HeartRequest? {
        guard let id = j["id"] as? String else { return nil }
        return HeartRequest(id: id, fromUser: string(j["fromUser"]), fromUserName: string(j["fromUserName"]),
                            toUser: string(j["toUser"]), createdAt: date(j["createdDate"]))
    }

    // MARK: Heartbeats

    static func heartbeats(bearer: String) async throws -> (items: [Item], pending: [PendingHeartbeat]) {
        let j = try await call("user/heartbeats", "GET", bearer: bearer) as? [String: Any] ?? [:]
        let items = ((j["heartbeats"] as? [[String: Any]]) ?? []).compactMap(item)
        let pend = ((j["pendingHeartbeats"] as? [[String: Any]]) ?? []).compactMap(pending)
        return (items, pend)
    }

    /// Uploads a heartbeat; returns its server id.
    static func create(_ hb: SavedHeartbeat, hasMemory: Bool, bearer: String) async throws -> String {
        let body: [String: Any] = ["pattern": hb.intervals, "name": hb.name, "color": hb.colorRGB & 0xFFFFFF,
                                   "isSelf": false, "createdDate": Int64(hb.createdAt.timeIntervalSince1970 * 1000),
                                   "hasMemory": hasMemory, "emails": hb.emails]
        let j = try await call("user/heartbeats", "POST", bearer: bearer, body: body) as? [String: Any]
        guard let id = j?["id"] as? String else { throw BondBackend.BackendError(message: "The Heart API returned no heartbeat id.") }
        return id
    }

    static func update(_ serverID: String, name: String, colorRGB: Int, hasMemory: Bool, emails: [String],
                       bearer: String) async throws {
        _ = try await call("user/heartbeats/\(serverID)", "PUT", bearer: bearer,
                           body: ["name": name, "color": colorRGB & 0xFFFFFF, "hasMemory": hasMemory, "emails": emails])
    }

    /// Accepts a pending heartbeat into the library; returns it.
    static func accept(_ id: String, bearer: String) async throws -> Item? {
        let j = try await call("user/heartbeats/\(id)", "PUT", bearer: bearer) as? [String: Any]
        return j.flatMap(item)
    }

    /// Deletes a heartbeat, or rejects a pending one.
    static func delete(_ id: String, bearer: String) async throws {
        do {
            _ = try await call("user/heartbeats/\(id)", "DELETE", bearer: bearer)
        } catch let e as BondBackend.BackendError where e.message.hasPrefix("HTTP 404") {
            // Already gone (the original treats 404 as done too).
        }
    }

    /// Shares a heartbeat with someone by their account email (they get it as pending).
    static func share(_ serverID: String, toEmail: String, message: String, bearer: String) async throws {
        _ = try await call("heartbeats/\(serverID)/requests", "PUT", bearer: bearer,
                           body: ["toUserEmail": toEmail.lowercased(), "message": message, "notify": true])
    }

    // MARK: Requests

    static func requests(bearer: String) async throws -> [HeartRequest] {
        ((try await call("requests", "GET", bearer: bearer) as? [[String: Any]]) ?? []).compactMap(request)
    }

    /// Asks someone (by email) for their heartbeat.
    static func ask(email: String, fromName: String, bearer: String) async throws {
        _ = try await call("requests", "POST", bearer: bearer,
                           body: ["fromUserName": fromName, "toUser": email.lowercased()])
    }

    static func deleteRequest(_ id: String, bearer: String) async throws {
        _ = try await call("requests/\(id)", "DELETE", bearer: bearer)
    }

    // MARK: Heartbeat count

    /// Shares how many times the heartbeat was felt since `since` with its `emails`.
    /// Returns the new `controlTimestamp`.
    static func shareCount(_ serverID: String, name: String, count: Int, since: Date, controlTimestamp: Int,
                           bearer: String) async throws -> Int {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let j = try await call("user/heartbeats/\(serverID)/count", "POST", bearer: bearer,
                               body: ["name": name, "count": count, "sinceDate": f.string(from: since),
                                      "controlTimestamp": controlTimestamp]) as? [String: Any]
        return (j?["controlTimestamp"] as? NSNumber)?.intValue ?? controlTimestamp
    }

    static func shareTotalCount(_ serverID: String, name: String, count: Int, bearer: String) async throws {
        _ = try await call("user/heartbeats/\(serverID)/total_count", "POST", bearer: bearer,
                           body: ["count": count, "name": name])
    }
}
