import Foundation

/// Touch Language (saved meanings shared with each partner), the home greeting, the next
/// encounter and the colour you give a partner. All of it lives on this phone and travels
/// to iCloud partners inside the encrypted profile record (see CloudRelay).
extension AppModel {
    // MARK: - Greeting / encounters

    func setGreeting(_ text: String, for bondID: String?) {
        store.setGreeting(text, for: bondID)
    }

    func setNextMeeting(_ date: Date?, for bondID: String?) {
        store.setNextMeeting(date, for: bondID)
    }

    /// Your colour for a partner.
    func setPartnerColor(_ rgb: Int, for bondID: String) {
        if let i = cloudPartners.firstIndex(where: { $0.id == bondID }) {
            cloudPartners[i].colorRGB = rgb
        }
    }

    // MARK: - Touch Language

    /// The selected partner's Touch Language (the library shared with them), or the local
    /// library when no partner is selected.
    var currentMeanings: [TouchMeaning] {
        if let bond = selectedPartner?.bond { return meanings(for: bond) }
        return store.meanings
    }

    /// A bond's Touch Language: the library shared with just that partner.
    func meanings(for bond: Bond) -> [TouchMeaning] {
        cloudLibrary(bond.id).filter { $0.deleted != true }
    }

    // MARK: - Touch Language shared with an iCloud partner

    /// The library shared with an iCloud partner, delete markers included.
    func cloudLibrary(_ bondID: String) -> [TouchMeaning] {
        store.cloudMeanings[bondID] ?? []
    }

    /// Once: the older single library becomes the shared library of each iCloud partner
    /// there was then. Partners added later start their own (nothing leaks between partners).
    func migrateMeaningLibraries() {
        let key = "MeaningsPerBondMigrated"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        // Not until the partners are actually known (a launch with iCloud unreachable lists none).
        guard !store.meanings.isEmpty, !(cloudPartners.isEmpty && cloudPending.isEmpty) else { return }
        for id in (cloudPartners.map(\.id) + cloudPending.map(\.id)) where store.cloudMeanings[id] == nil {
            store.cloudMeanings[id] = store.meanings.map { var m = $0; m.updatedAt = m.updatedAt ?? Date(); return m }
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Changes the shared library and sends it to the partner (in the encrypted profile).
    private func changeCloudLibrary(_ bondID: String, _ change: (inout [TouchMeaning]) -> Void) {
        var lib = cloudLibrary(bondID)
        change(&lib)
        store.cloudMeanings[bondID] = lib
        Task { await publishMeanings(bondID: bondID) }
    }

    /// What we share: no local-only state (the New badge, and `serverID`, an id older
    /// versions kept from the original Bond Touch servers).
    func sharedLibrary(_ bondID: String) -> [TouchMeaning] {
        cloudLibrary(bondID).map { var m = $0; m.isNew = false; m.serverID = nil; return m }
    }

    func publishMeanings(bondID: String) async {
        guard let bond = cloudPartners.first(where: { $0.id == bondID })?.bond else { return }
        let p = store.profile
        do {
            try await relay.sendProfile(name: p.name.isEmpty ? "Me" : p.name, colorRGB: p.colorRGB,
                                        photo: myPhotoFileURL, pushToken: myPushToken,
                                        meanings: sharedLibrary(bondID), about: p.about, bond: bond, senderID: myUserID)
        } catch {
            NetLog.shared.log(.fail, "iCloud: Touch Language not sent", error.localizedDescription)
        }
    }

    /// Takes in the partner's copy: for each meaning the newer edit wins; ones only they have
    /// are added with a New badge (a same-named one we already have isn't doubled).
    func mergeMeanings(_ incoming: [TouchMeaning], bondID: String) {
        var lib = cloudLibrary(bondID)
        var changed = false
        for var m in incoming {
            if let i = lib.firstIndex(where: { $0.id == m.id }) {
                guard (m.updatedAt ?? .distantPast) > (lib[i].updatedAt ?? .distantPast) else { continue }
                m.isNew = lib[i].isNew
                m.serverID = lib[i].serverID
                lib[i] = m
                changed = true
            } else if m.deleted != true,
                      !lib.contains(where: { $0.deleted != true && $0.label.lowercased() == m.label.lowercased() }) {
                m.isNew = true
                lib.append(m)
                changed = true
            }
        }
        if changed { store.cloudMeanings[bondID] = lib }
    }

    /// Clears a meaning's New badge (local only).
    func markMeaningSeen(_ meaning: TouchMeaning) {
        guard meaning.isNew else { return }
        if let bond = selectedPartner?.bond {
            var lib = cloudLibrary(bond.id)
            if let i = lib.firstIndex(where: { $0.id == meaning.id }) { lib[i].isNew = false; store.cloudMeanings[bond.id] = lib }
        } else if let i = store.meanings.firstIndex(where: { $0.id == meaning.id }) {
            store.meanings[i].isNew = false
        }
    }

    /// The saved meaning a touch closely matches, if any — so a touch that's really
    /// "Love you" (made on the screen, the bracelet or the watch) is treated as it.
    func matchingMeaning(pattern: [Int], generation: Int, in list: [TouchMeaning]) -> TouchMeaning? {
        let scored = list.filter { !$0.pattern.isEmpty }
            .map { ($0, TouchPattern.matchScore(pattern, generation: generation, $0.pattern, generation: $0.touchGeneration)) }
            .sorted { $0.1 > $1.1 }
        guard let best = scored.first, best.1 >= TouchPattern.matchThreshold(generation, best.0.touchGeneration) else { return nil }
        // Two saved touches nearly as close as each other: too close to call, so neither.
        if scored.count > 1, best.1 - scored[1].1 < 0.04 { return nil }
        return best.0
    }

    /// For the touch bar: the selected partner's meaning this touch matches, if any.
    func closeMeaning(pattern: [Int], generation: Int) -> TouchMeaning? {
        matchingMeaning(pattern: pattern, generation: generation, in: currentMeanings)
    }

    /// The meaning to show over a touch on Home: the one it was sent / received as, or —
    /// for older touches and ones that came without — a saved meaning it closely matches.
    func meaningTag(for touch: TouchMessage) -> (label: String, emoji: String)? {
        let list = partners.first { $0.id == touch.bondID }.map { meanings(for: $0.bond) } ?? store.meanings
        if let label = touch.meaningLabel, !label.isEmpty {
            let emoji = touch.meaningEmoji ?? list.first { $0.label == label }?.emoji ?? ""
            return (label, emoji)
        }
        guard let m = matchingMeaning(pattern: touch.pattern, generation: touch.generation, in: list) else { return nil }
        return (m.label, m.emoji)
    }

    func addMeaning(_ meaning: TouchMeaning) async {
        guard let bond = selectedPartner?.bond else { store.meanings.append(meaning); return }
        var m = meaning
        m.updatedAt = Date()
        changeCloudLibrary(bond.id) { $0.append(m) }
        Task { await notifyPartner(bond.id, "added \u{201C}\(m.label)\u{201D} to your Touch Language 🫶") }
    }

    /// Saves an edited meaning (name, emoji, colours, favourite): in the library shared with
    /// the selected partner, else in the local library.
    func updateMeaning(_ meaning: TouchMeaning) async {
        if let bond = selectedPartner?.bond {
            var m = meaning
            m.updatedAt = Date()
            changeCloudLibrary(bond.id) { lib in if let i = lib.firstIndex(where: { $0.id == m.id }) { lib[i] = m } }
            Task { await notifyPartner(bond.id, "changed \u{201C}\(m.label)\u{201D} in your Touch Language 🫶") }
        } else if let i = store.meanings.firstIndex(where: { $0.id == meaning.id }) {
            store.meanings[i] = meaning
        }
    }

    func deleteMeaning(_ meaning: TouchMeaning) async {
        if let bond = selectedPartner?.bond {
            // Kept as a marker so it's deleted on the partner's phone too.
            changeCloudLibrary(bond.id) { lib in
                if let i = lib.firstIndex(where: { $0.id == meaning.id }) { lib[i].deleted = true; lib[i].updatedAt = Date() }
            }
            Task { await notifyPartner(bond.id, "removed \u{201C}\(meaning.label)\u{201D} from your Touch Language") }
            return
        }
        store.meanings.removeAll { $0.id == meaning.id }
    }
}
