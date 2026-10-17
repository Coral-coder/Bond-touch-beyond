import Foundation
import UIKit

/// The Bond Heart library, kept on this device: saved heartbeats (JSON in Application
/// Support), their memory photos (JPEG files beside it), which one the pendant wears, and
/// what the original Heart API last reported (pending heartbeats and requests).
@MainActor
final class HeartLibrary: ObservableObject {
    @Published private(set) var items: [SavedHeartbeat] = []
    /// The heartbeat written to the pendant last.
    @Published private(set) var wornID: UUID?
    @Published private(set) var wornAt: Date?
    /// The pendant's played counter when the heartbeat was put on (the count shared is the
    /// reading minus this).
    @Published private(set) var countBaseline: Int?
    /// When the heartbeat count was last shared (the original allows once every 24 hours).
    @Published var lastCountShare: Date?
    /// `controlTimestamp` the server returned last; sent back with the next count.
    var controlTimestamp = 0

    // From the original Heart API (not stored).
    @Published var pending: [PendingHeartbeat] = []
    @Published var requests: [HeartRequest] = []
    @Published var syncStatus = ""
    @Published var lastSync: Date?
    /// Server ids deleted here that still need deleting on the server.
    private(set) var deletedServerIDs: [String] = []

    private struct Saved: Codable {
        var items: [SavedHeartbeat]
        var wornID: UUID?
        var wornAt: Date?
        var countBaseline: Int?
        var lastCountShare: Date?
        var controlTimestamp: Int
        var deletedServerIDs: [String]
    }

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("BondHeart", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private static var file: URL { folder.appendingPathComponent("library.json") }

    init() {
        if let data = try? Data(contentsOf: Self.file),
           let s = try? JSONDecoder().decode(Saved.self, from: data) {
            items = s.items
            wornID = s.wornID
            wornAt = s.wornAt
            countBaseline = s.countBaseline
            lastCountShare = s.lastCountShare
            controlTimestamp = s.controlTimestamp
            deletedServerIDs = s.deletedServerIDs
        }
    }

    func save() {
        let s = Saved(items: items, wornID: wornID, wornAt: wornAt, countBaseline: countBaseline,
                      lastCountShare: lastCountShare, controlTimestamp: controlTimestamp,
                      deletedServerIDs: deletedServerIDs)
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: Self.file, options: .atomic) }
    }

    var worn: SavedHeartbeat? { items.first { $0.id == wornID } }

    func item(_ id: UUID) -> SavedHeartbeat? { items.first { $0.id == id } }

    /// Adds or replaces a heartbeat (newest first).
    func upsert(_ hb: SavedHeartbeat) {
        if let i = items.firstIndex(where: { $0.id == hb.id }) { items[i] = hb } else { items.insert(hb, at: 0) }
        save()
    }

    func delete(_ id: UUID) {
        guard let hb = item(id) else { return }
        if let sid = hb.serverID { deletedServerIDs.append(sid) }
        items.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: photoURL(id))
        if wornID == id { wornID = nil; wornAt = nil; countBaseline = nil }
        save()
    }

    func serverDeleteDone(_ serverID: String) {
        deletedServerIDs.removeAll { $0 == serverID }
        save()
    }

    func markWorn(_ id: UUID, baseline: Int?) {
        wornID = id
        wornAt = Date()
        countBaseline = baseline
        save()
    }

    // MARK: Memory photos

    func photoURL(_ id: UUID) -> URL { Self.folder.appendingPathComponent("\(id.uuidString).jpg") }

    func photo(_ id: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: photoURL(id)) else { return nil }
        return UIImage(data: data)
    }

    func photoData(_ id: UUID) -> Data? { try? Data(contentsOf: photoURL(id)) }

    /// Stores (or with nil, removes) a heartbeat's memory photo, as a JPEG at most 1600 px.
    func setPhoto(_ image: UIImage?, for id: UUID) {
        guard var hb = item(id) else { return }
        if let image {
            let scale = min(1, 1600 / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            if let jpeg = resized.jpegData(compressionQuality: 0.85) { try? jpeg.write(to: photoURL(id), options: .atomic) }
            hb.hasPhoto = true
        } else {
            try? FileManager.default.removeItem(at: photoURL(id))
            hb.hasPhoto = false
        }
        hb.dirty = hb.serverID != nil
        upsert(hb)
    }

    func setPhotoData(_ data: Data, for id: UUID) {
        try? data.write(to: photoURL(id), options: .atomic)
        if var hb = item(id), !hb.hasPhoto { hb.hasPhoto = true; upsert(hb) }
    }
}
