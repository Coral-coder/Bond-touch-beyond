import Foundation

/// A recorded heartbeat in the Bond Heart library: real inter-beat intervals (ms), as the
/// original's `HeartbeatItem.pattern`, plus its name, colour and memory.
struct SavedHeartbeat: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// Its id on the original Heart API, once uploaded (or when it came from there).
    var serverID: String?
    /// Whose heartbeat it is ("Who's in your heart?").
    var name: String
    var colorRGB: Int
    /// A note kept with it. The original's "memory" is a photo; that's `hasPhoto`.
    var memory: String = ""
    /// A memory photo is stored locally (`HeartLibrary.photoURL`).
    var hasPhoto: Bool = false
    /// Inter-beat intervals in milliseconds.
    var intervals: [Int]
    var createdAt: Date = Date()
    /// The account that recorded it (server `createdBy`), when known.
    var createdBy: String?
    /// Recorded by this user (server `isSelf`).
    var isSelf: Bool = true
    /// Who may see its heartbeat count (server `emails`, up to 3).
    var emails: [String] = []
    var source: Source = .camera
    /// Changed locally since the last upload.
    var dirty: Bool = false

    enum Source: String, Codable {
        case camera, watch, heartRate, received, server
    }

    /// Average heart rate over the recording.
    var bpm: Int {
        let valid = intervals.filter { $0 > 0 }
        guard !valid.isEmpty else { return 60 }
        let mean = Double(valid.reduce(0, +)) / Double(valid.count)
        return min(220, max(30, Int((60_000 / mean).rounded())))
    }

    /// Total length of the recording, in seconds.
    var seconds: Double { Double(intervals.reduce(0, +)) / 1000 }

    var title: String { name.isEmpty ? "Heartbeat" : "\(name)’s heartbeat" }
}

/// A heartbeat someone shared with this account that hasn't been accepted yet (server
/// `pendingHeartbeats`; the original's "Received from:").
struct PendingHeartbeat: Identifiable, Equatable {
    let id: String
    let name: String
    let colorRGB: Int
    let createdBy: String
    let createdAt: Date
    let message: String
    let intervals: [Int]
}

/// A request for a heartbeat (server `/heart/api/v2/requests`): sent by this account
/// ("Pending request to:") or to it ("… is asking for your heartbeat").
struct HeartRequest: Identifiable, Equatable {
    let id: String
    let fromUser: String
    let fromUserName: String
    let toUser: String
    let createdAt: Date
}
