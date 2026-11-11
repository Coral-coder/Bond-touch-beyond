import Foundation

/// A partner taken off the list because their bond couldn't be found in iCloud, kept for 30
/// days so it can be put back (People → Recently removed → Restore).
struct RemovedBond: Codable, Identifiable, Equatable {
    var id: String          // the bond code
    var isOwner: Bool
    var name: String
    var colorRGB: Int
    var removedAt: Date
}

/// Keeps partners from vanishing on a bad iCloud read. A bond whose record iCloud doesn't
/// return is kept as a partner; only after it has been missing on 3 launches spread over at
/// least 3 days is it taken off the list, and even then it goes to "Recently removed" for 30
/// days instead of being forgotten.
enum BondKeeper {
    static let missesBeforeRemoving = 3
    static let minimumDaysMissing: TimeInterval = 3 * 24 * 3600
    static let keepRemovedFor: TimeInterval = 30 * 24 * 3600

    private struct Miss: Codable { var first: Date; var count: Int; var last: Date }
    private struct Known: Codable { var name: String; var colorRGB: Int }

    private static let missKey = "bondKeeper.misses"
    private static let knownKey = "bondKeeper.known"
    private static let removedKey = "bondKeeper.removed"

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    private static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// The last name and colour seen for each partner, so a kept or removed one still shows who it is.
    static func remember(_ partners: [Partner]) {
        var known = load([String: Known].self, knownKey) ?? [:]
        var changed = false
        for p in partners where !p.bond.legacy && !["", "Partner", "Pending…"].contains(p.displayName) {
            let k = Known(name: p.displayName, colorRGB: p.colorRGB)
            if known[p.id]?.name != k.name || known[p.id]?.colorRGB != k.colorRGB { known[p.id] = k; changed = true }
        }
        if changed { save(known, knownKey) }
    }

    static func name(_ code: String) -> String? { load([String: Known].self, knownKey)?[code]?.name }
    static func color(_ code: String) -> Int? { load([String: Known].self, knownKey)?[code]?.colorRGB }

    /// The bond was found: forget any earlier misses.
    static func found(_ code: String) {
        var misses = load([String: Miss].self, missKey) ?? [:]
        guard misses.removeValue(forKey: code) != nil else { return }
        save(misses, missKey)
    }

    /// The bond wasn't found on this launch. Returns true once it has been missing long enough
    /// to take it off the list. Several reads in one launch count once (an hour apart at least).
    static func missed(_ code: String, now: Date = Date()) -> Bool {
        var misses = load([String: Miss].self, missKey) ?? [:]
        var m = misses[code] ?? Miss(first: now, count: 0, last: .distantPast)
        if now.timeIntervalSince(m.last) >= 3600 { m.count += 1; m.last = now }
        misses[code] = m
        save(misses, missKey)
        return m.count >= missesBeforeRemoving && now.timeIntervalSince(m.first) >= minimumDaysMissing
    }

    static func removed() -> [RemovedBond] {
        let cutoff = Date().addingTimeInterval(-keepRemovedFor)
        return (load([RemovedBond].self, removedKey) ?? []).filter { $0.removedAt > cutoff }
    }

    static func addRemoved(_ r: RemovedBond) {
        var list = removed().filter { $0.id != r.id }
        list.insert(r, at: 0)
        save(list, removedKey)
        found(r.id)
    }

    static func takeRemoved(_ code: String) {
        save(removed().filter { $0.id != code }, removedKey)
    }
}

extension AppModel {
    /// The bonds to show after loading from iCloud: every one iCloud returned, plus every one it
    /// didn't return that hasn't yet been missing long enough to remove. Never drops a partner
    /// on a single bad read.
    func keepPartners(found: [Bond], missing: [String: Bool]) -> [Bond] {
        found.forEach { BondKeeper.found($0.id) }
        var kept = found
        for (code, isOwner) in missing {
            if BondKeeper.missed(code) {
                let name = BondKeeper.name(code) ?? "Partner"
                BondKeeper.addRemoved(RemovedBond(id: code, isOwner: isOwner, name: name,
                                                  colorRGB: BondKeeper.color(code) ?? 0xFF4081, removedAt: Date()))
                store.cloudBondCodes[code] = nil
                NetLog.shared.log(.fail, "iCloud: \(name)'s bond has been missing for days, moved to Recently removed")
            } else {
                NetLog.shared.log(.fail, "iCloud didn't return a bond; keeping the partner", BondKeeper.name(code) ?? code.prefix(6).description)
                kept.append(Bond(id: code, partnerName: BondKeeper.name(code) ?? "Partner", isOwner: isOwner))
            }
        }
        removedBonds = BondKeeper.removed()
        return kept
    }

    /// Puts a removed partner back: the bond code returns to this phone and syncing resumes.
    func restoreBond(_ r: RemovedBond) async {
        BondKeeper.takeRemoved(r.id)
        removedBonds = BondKeeper.removed()
        store.cloudBondCodes[r.id] = r.isOwner
        if !cloudPartners.contains(where: { $0.id == r.id }) {
            var partner = cloudPartner(Bond(id: r.id, partnerName: r.name, isOwner: r.isOwner))
            partner.colorRGB = r.colorRGB
            cloudPartners.append(partner)
            loadCachedPhoto(bondID: r.id)
        }
        selectedPartnerID = r.id
        profileSyncedBondIDs.remove(r.id)
        NetLog.shared.log(.ok, "Restored \(r.name)")
        await publishProfile()
        await refreshAll()
        startCloudPolling()
    }

    /// Clears a removed partner for good.
    func forgetRemovedBond(_ r: RemovedBond) {
        BondKeeper.takeRemoved(r.id)
        removedBonds = BondKeeper.removed()
    }
}
