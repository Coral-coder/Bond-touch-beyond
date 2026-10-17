import Foundation
import UIKit

/// Bond Heart: the pendant (`pendant`), the local library (`heartLibrary`), and — with an
/// original Bond Touch account — the original Heart API for sharing and requests.
extension AppModel {

    // MARK: - Pendant

    /// Writes a heartbeat to the pendant and remembers it as the one being worn (with the
    /// pendant's played counter at that moment, for the heartbeat count).
    func wearHeartbeat(_ hb: SavedHeartbeat) async throws {
        try await pendant.wear(intervals: hb.intervals)
        let baseline = try? await pendant.readCounts().played
        heartLibrary.markWorn(hb.id, baseline: baseline)
        NetLog.shared.log(.ok, "Heart: wearing \(hb.title)", "\(hb.intervals.count) intervals, \(hb.bpm) BPM")
    }

    // MARK: - iCloud / original-app partners

    /// Sends a saved heartbeat to a partner as a heartbeat touch, like "Send my heartbeat":
    /// the EKG at its BPM on their bracelet and screen, in their history.
    func sendSavedHeartbeat(_ hb: SavedHeartbeat, toBondID: String) async -> Bool {
        guard let bond = partners.first(where: { $0.id == toBondID })?.bond else { return false }
        let bpm = hb.bpm
        statusLine = ""
        if bond.legacy {
            await sendTouch(pattern: EKG.onOff(bpm: bpm), generation: 2, colorRGB: hb.colorRGB,
                            toBondID: bond.id, matchMeaning: false, heartbeatBPM: bpm)
        } else {
            await sendTouch(pattern: EKG.samples(bpm: bpm), generation: 3, colorRGB: hb.colorRGB,
                            toBondID: bond.id, matchMeaning: false, heartbeatBPM: bpm)
        }
        return !statusLine.hasPrefix("Send failed")
    }

    // MARK: - Original Heart API

    /// Syncs with the original Heart API: pushes local deletions and edits, then pulls the library, pending heartbeats and requests.
    func heartSync() async {
        guard legacySignedIn else { heartLibrary.syncStatus = "Sign in with your Bond Touch account to share heartbeats."; return }
        heartLibrary.syncStatus = "Syncing…"
        do {
            let token = try await legacyToken()
            for sid in heartLibrary.deletedServerIDs {
                try await HeartAPI.delete(sid, bearer: token)
                heartLibrary.serverDeleteDone(sid)
            }
            // Edits to heartbeats already on the account. New recordings stay on this phone
            // until they're shared (the original uploads every one).
            for hb in heartLibrary.items where hb.serverID != nil && hb.dirty {
                _ = try await upload(hb, token: token)
            }
            let (items, pending) = try await HeartAPI.heartbeats(bearer: token)
            for it in items { await merge(it, token: token) }
            heartLibrary.pending = pending
            heartLibrary.requests = try await HeartAPI.requests(bearer: token)
            heartLibrary.lastSync = Date()
            heartLibrary.syncStatus = ""
        } catch {
            heartLibrary.syncStatus = error.localizedDescription
            NetLog.shared.log(.fail, "Heart API sync", error.localizedDescription)
        }
    }

    /// Uploads (or updates) a heartbeat; returns its server id. Its memory photo is uploaded
    /// to Firebase Storage `memories/<uid>/<id>` as the original — which App Check blocks
    /// for this app, so `hasMemory` stays false unless that upload worked.
    @discardableResult
    func upload(_ hb: SavedHeartbeat, token: String) async throws -> String {
        var hb = hb
        var hasMemory = false
        if let sid = hb.serverID {
            if hb.hasPhoto { hasMemory = await uploadMemory(hb, serverID: sid, token: token) }
            try await HeartAPI.update(sid, name: hb.name, colorRGB: hb.colorRGB, hasMemory: hasMemory,
                                      emails: hb.emails, bearer: token)
        } else {
            let sid = try await HeartAPI.create(hb, hasMemory: false, bearer: token)
            hb.serverID = sid
            if hb.hasPhoto, await uploadMemory(hb, serverID: sid, token: token) {
                try await HeartAPI.update(sid, name: hb.name, colorRGB: hb.colorRGB, hasMemory: true,
                                          emails: hb.emails, bearer: token)
            }
        }
        hb.dirty = false
        heartLibrary.upsert(hb)
        return hb.serverID ?? ""
    }

    private func uploadMemory(_ hb: SavedHeartbeat, serverID: String, token: String) async -> Bool {
        guard let data = heartLibrary.photoData(hb.id), let uid = BondBackend.tokenUID(token) else { return false }
        do {
            try await FirebaseStorage.upload(data, to: "memories/\(uid)/\(serverID)", contentType: "image/jpeg", token: token)
            return true
        } catch {
            NetLog.shared.log(.fail, "Heart memory photo upload", error.localizedDescription)
            return false
        }
    }

    /// Adds or refreshes a server heartbeat in the local library (local edits win until
    /// they're uploaded).
    private func merge(_ it: HeartAPI.Item, token: String) async {
        var hb = heartLibrary.items.first { $0.serverID == it.id }
            ?? SavedHeartbeat(serverID: it.id, name: it.name, colorRGB: it.colorRGB, intervals: it.intervals,
                              createdAt: it.createdAt, createdBy: it.createdBy, isSelf: it.isSelf,
                              emails: it.emails, source: it.isSelf ? .server : .received)
        if !hb.dirty {
            hb.name = it.name
            hb.colorRGB = it.colorRGB
            hb.emails = it.emails
            if !it.intervals.isEmpty { hb.intervals = it.intervals }
        }
        heartLibrary.upsert(hb)
        if it.hasMemory, !hb.hasPhoto { await downloadMemory(hb, serverID: it.id, owner: it.createdBy, token: token) }
    }

    /// The memory photo, from `memories/<owner uid>/<id>` (owner = `createdBy`, which is
    /// presumably the Firebase uid — a guess). App Check normally blocks this.
    private func downloadMemory(_ hb: SavedHeartbeat, serverID: String, owner: String, token: String) async {
        let uid = owner.isEmpty ? (BondBackend.tokenUID(token) ?? "") : owner
        guard !uid.isEmpty else { return }
        if let data = try? await FirebaseStorage.download("memories/\(uid)/\(serverID)", token: token) {
            heartLibrary.setPhotoData(data, for: hb.id)
        }
    }

    /// Accepts a heartbeat someone shared into the library.
    func acceptPending(_ p: PendingHeartbeat) async -> String? {
        do {
            let token = try await legacyToken()
            let it = try await HeartAPI.accept(p.id, bearer: token)
            let hb = SavedHeartbeat(serverID: it?.id ?? p.id, name: it?.name ?? p.name, colorRGB: it?.colorRGB ?? p.colorRGB,
                                    memory: p.message, intervals: (it?.intervals.isEmpty == false ? it?.intervals : nil) ?? p.intervals,
                                    createdAt: p.createdAt, createdBy: p.createdBy, isSelf: false, source: .received)
            heartLibrary.upsert(hb)
            heartLibrary.pending.removeAll { $0.id == p.id }
            return nil
        } catch { return error.localizedDescription }
    }

    func rejectPending(_ p: PendingHeartbeat) async -> String? {
        do {
            let token = try await legacyToken()
            try await HeartAPI.delete(p.id, bearer: token)
            heartLibrary.pending.removeAll { $0.id == p.id }
            return nil
        } catch { return error.localizedDescription }
    }

    /// Shares a heartbeat by email: they receive it as pending (and a notification or email
    /// from the original servers). Uploads it first if needed.
    func shareHeartbeat(_ hb: SavedHeartbeat, toEmail: String, message: String) async -> String? {
        do {
            let token = try await legacyToken()
            let sid: String
            if let existing = hb.serverID, !hb.dirty { sid = existing } else { sid = try await upload(hb, token: token) }
            try await HeartAPI.share(sid, toEmail: toEmail, message: message, bearer: token)
            NetLog.shared.log(.ok, "Heart: shared \(hb.title) with \(toEmail)")
            return nil
        } catch { return error.localizedDescription }
    }

    /// Asks someone for their heartbeat by email.
    func askForHeartbeat(email: String) async -> String? {
        do {
            let token = try await legacyToken()
            let name = store.profile.name.isEmpty ? "Me" : store.profile.name
            try await HeartAPI.ask(email: email, fromName: name, bearer: token)
            heartLibrary.requests = (try? await HeartAPI.requests(bearer: token)) ?? heartLibrary.requests
            return nil
        } catch { return error.localizedDescription }
    }

    func deleteHeartRequest(_ r: HeartRequest) async -> String? {
        do {
            let token = try await legacyToken()
            try await HeartAPI.deleteRequest(r.id, bearer: token)
            heartLibrary.requests.removeAll { $0.id == r.id }
            return nil
        } catch { return error.localizedDescription }
    }

    /// Answers a request: shares the heartbeat with whoever asked, then clears the request.
    func answerRequest(_ r: HeartRequest, with hb: SavedHeartbeat) async -> String? {
        if let err = await shareHeartbeat(hb, toEmail: r.fromUser, message: "") { return err }
        _ = await deleteHeartRequest(r)
        return nil
    }

    /// A request sent to this account (vs. one this account sent).
    func isReceived(_ r: HeartRequest) -> Bool {
        let me = store.legacyEmail.lowercased()
        return !me.isEmpty && r.toUser.lowercased() == me
    }

    // MARK: - Heartbeat count

    /// How many times the worn heartbeat was felt since it was put on (pendant's played
    /// counter minus the reading at that time).
    func feltCount() async throws -> Int {
        let played = try await pendant.readCounts().played
        let base = heartLibrary.countBaseline ?? 0
        return played >= base ? played - base : played
    }

    /// Shares the worn heartbeat's count with the people in its `emails` (once a day, as
    /// the original).
    func shareFeltCount() async -> String? {
        guard var hb = heartLibrary.worn else { return "You're not wearing any heartbeat." }
        if let last = heartLibrary.lastCountShare, Date().timeIntervalSince(last) < 24 * 3600 {
            return "You can share the count once every 24 hours."
        }
        guard !hb.emails.isEmpty else { return "Choose who can see this heartbeat count by adding their emails." }
        do {
            let count = try await feltCount()
            guard count > 0 else { return "Feel the heartbeat so you can share your count." }
            let token = try await legacyToken()
            if hb.serverID == nil || hb.dirty {
                _ = try await upload(hb, token: token)
                hb = heartLibrary.item(hb.id) ?? hb
            }
            guard let sid = hb.serverID else { return "Couldn't upload the heartbeat." }
            let name = store.profile.name.isEmpty ? "Me" : store.profile.name
            heartLibrary.controlTimestamp = try await HeartAPI.shareCount(
                sid, name: name, count: count, since: heartLibrary.wornAt ?? hb.createdAt,
                controlTimestamp: heartLibrary.controlTimestamp, bearer: token)
            heartLibrary.lastCountShare = Date()
            heartLibrary.save()
            return nil
        } catch { return error.localizedDescription }
    }
}
