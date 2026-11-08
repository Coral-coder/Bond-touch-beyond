import Foundation
import UIKit

/// Bond Heart: the pendant (`pendant`) and the local library (`heartLibrary`).
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

    // MARK: - iCloud partners

    /// Sends a saved heartbeat to a partner as a heartbeat touch, like "Send my heartbeat":
    /// the EKG at its BPM on their bracelet and screen, in their history.
    func sendSavedHeartbeat(_ hb: SavedHeartbeat, toBondID: String) async -> Bool {
        guard let bond = partners.first(where: { $0.id == toBondID })?.bond else { return false }
        let bpm = hb.bpm
        statusLine = ""
        await sendTouch(pattern: EKG.samples(bpm: bpm), generation: 3, colorRGB: hb.colorRGB,
                        toBondID: bond.id, matchMeaning: false, heartbeatBPM: bpm)
        return !statusLine.hasPrefix("Send failed")
    }

    // MARK: - Heartbeat count

    /// How many times the worn heartbeat was felt since it was put on (pendant's played
    /// counter minus the reading at that time).
    func feltCount() async throws -> Int {
        let played = try await pendant.readCounts().played
        let base = heartLibrary.countBaseline ?? 0
        return played >= base ? played - base : played
    }
}
