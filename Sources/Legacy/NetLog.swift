import Foundation

/// A small in-memory log of recent network calls and touch events, shown in the debug panel
/// (tap the partner bar 5×). It exists to answer one question when a touch doesn't arrive:
/// where did it break — the send, the server's response, or the receiving side?
///
/// Nothing here leaves the device; it is kept in memory (the last 100 entries) and cleared
/// when the app is relaunched.
@MainActor
final class NetLog: ObservableObject {
    static let shared = NetLog()

    struct Entry: Identifiable {
        let id = UUID()
        let at = Date()
        let kind: Kind
        let title: String
        let detail: String
        enum Kind { case send, ok, fail, recv }
    }

    @Published private(set) var entries: [Entry] = []

    private init() {}

    func log(_ kind: Entry.Kind, _ title: String, _ detail: String = "") {
        entries.insert(Entry(kind: kind, title: title, detail: String(detail.prefix(500))), at: 0)
        if entries.count > 100 { entries.removeLast(entries.count - 100) }
    }

    /// Thread-safe entry point for code not on the main actor.
    nonisolated func record(_ kind: Entry.Kind, _ title: String, _ detail: String = "") {
        Task { @MainActor in self.log(kind, title, detail) }
    }

    func clear() { entries.removeAll() }
}
