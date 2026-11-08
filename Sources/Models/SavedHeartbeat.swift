import Foundation

/// A recorded heartbeat in the Bond Heart library: real inter-beat intervals (ms), as the
/// original's `HeartbeatItem.pattern`, plus its name, colour and memory.
struct SavedHeartbeat: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// Unused: its id on the original Bond Touch Heart API, from older versions. Kept so
    /// saved libraries still decode.
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
    /// Unused: who could see its heartbeat count on the original Heart API. Kept so saved
    /// libraries still decode.
    var emails: [String] = []
    var source: Source = .camera
    /// Unused: "changed since the last upload" for the original Heart API. Kept for decoding.
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
