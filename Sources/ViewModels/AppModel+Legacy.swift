import CoreLocation
import Foundation

/// The original Bond Touch backend (api.bond-touch.com), running in parallel with iCloud.
///
/// Mirrors the original app's sync: it pulls `GET bond/api/v4/bonds` (partners, invites,
/// received touches, meanings, greeting, encounter), plays new touches on the bracelet and
/// acknowledges them, and pushes the user's own changes with the matching REST calls. The
/// original app is woken by FCM pushes sent to its own app id, which this app cannot
/// receive, so it polls instead while in the foreground.
extension AppModel {
    private static let pollSeconds: UInt64 = 4
    private static let seenTouchesKey = "LegacySeenTouchIDs"

    var legacySignedIn: Bool { store.useLegacyFirebase && !store.firebaseAuthToken.isEmpty }

    // MARK: - Session

    /// A valid ID token, refreshed with the refresh token when it is about to expire.
    func legacyToken() async throws -> String {
        let token = store.firebaseAuthToken
        if let exp = BondBackend.tokenExpiry(token), exp.timeIntervalSinceNow > 300 { return token }
        guard !store.legacyRefreshToken.isEmpty else { return token }
        let session = try await BondBackend.refreshSession(refreshToken: store.legacyRefreshToken)
        store.firebaseAuthToken = session.idToken
        store.legacyRefreshToken = session.refreshToken
        return session.idToken
    }

    // MARK: - Sync loop

    func startLegacySync() {
        guard legacySignedIn, legacyTask == nil else { return }
        legacyStatus = "Connecting…"
        legacyTask = Task { [weak self] in
            await self?.legacySetOnline(true)
            while !Task.isCancelled {
                await self?.legacySyncOnce()
                try? await Task.sleep(nanoseconds: Self.pollSeconds * 1_000_000_000)
            }
        }
    }

    func stopLegacySync() {
        legacyTask?.cancel()
        legacyTask = nil
    }

    /// Called on logout: stop syncing and drop every original-backend partner.
    func resetLegacy() {
        stopLegacySync()
        legacyPartners = []
        legacyPending = []
        incomingInvites = []
        legacyMeanings = [:]
        legacyPrimed = false
        legacyStatus = "Not signed in"
        UserDefaults.standard.removeObject(forKey: Self.seenTouchesKey)
        resetLegacyChat()
        if let id = selectedPartnerID, !partners.contains(where: { $0.id == id }) {
            selectedPartnerID = partners.first?.id
        }
    }

    private var seenTouchIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.seenTouchesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(2000)), forKey: Self.seenTouchesKey) }
    }

    func legacySyncOnce() async {
        guard legacySignedIn else { return }
        do {
            let token = try await legacyToken()
            let bonds = try await BondBackend.getBonds(bearer: token)
            await apply(bonds, token: token)
            legacyCycle += 1
            // Presence and partner details change slowly; refresh them every few cycles.
            if legacyCycle % 4 == 1 { await legacyRefreshDetails(token: token) }
            if legacyCycle % 8 == 1 { await legacySetOnline(true) }
            if legacyCycle == 1 { loadMyPhoto() }
            legacyLastSync = Date()
            legacyStatus = "Synced"
            if legacyCycle == 1 { updateKeepAlive() }
        } catch {
            legacyStatus = "Sync error: \(error.localizedDescription)"
        }
    }

    private func apply(_ bonds: [[String: Any]], token: String) async {
        var partners: [Partner] = []
        var pending: [Bond] = []
        var incoming: [Bond] = []
        var seen = seenTouchIDs
        var toAck: [(bondId: String, touchId: String)] = []
        var newTouches: [TouchMessage] = []
        let firstSync = !legacyPrimed

        for b in bonds {
            guard let id = b["bondId"] as? String else { continue }
            let status = (b["status"] as? String) ?? ""
            let profile = (b["profile"] as? [String: Any]) ?? [:]
            let settings = (b["settings"] as? [String: Any]) ?? [:]
            let email = (b["email"] as? String) ?? ""
            let name = ((profile["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }) ?? email
            let bond = Bond(id: id, partnerName: name.isEmpty ? "Partner" : name, isOwner: false,
                            pending: status != "BONDED", legacy: true)
            legacyPartnerIcons[id] = (settings["icon"] as? String) ?? ""
            legacyPartnerAccounts[id] = (uid: (b["firebaseId"] as? String) ?? "",
                                         phone: (b["phoneNumber"] as? String) ?? "")

            switch status {
            case "REQUESTED": pending.append(bond); continue
            case "RECEIVED":  incoming.append(bond); continue
            case "BONDED":    break
            default:          continue
            }

            // Partner colour: your custom colour for them, else their profile colour.
            let color = BondBackend.rgb(fromAndroid: settings["color"])
                ?? BondBackend.rgb(fromAndroid: profile["color"]) ?? 0xFF4081
            if (profile["hasImage"] as? Bool) == true {
                loadPartnerPhoto(bondID: id, uid: (b["firebaseId"] as? String) ?? "",
                                 version: (profile["version"] as? NSNumber)?.int64Value ?? 0)
            }
            // Keep the presence / location learned by the slower refreshes.
            let known = legacyPartners.first { $0.id == id }
            partners.append(Partner(bond: bond, displayName: bond.partnerName, colorRGB: color,
                                    online: known?.online ?? false, lastSeen: known?.lastSeen,
                                    latitude: known?.latitude, longitude: known?.longitude))

            // A partner who is on iCloud with you syncs through iCloud only: ignore their
            // touches, meanings, greeting and encounter from the original backend.
            if migratedLegacyIDs.contains(id) { continue }

            let meanings = ((b["meanings"] as? [[String: Any]]) ?? []).compactMap(BondBackend.meaning(from:))
            legacyMeanings[id] = meanings

            if let msg = b["dashboardMessage"] as? String, !msg.isEmpty, store.greetings[id] != msg {
                store.greetings[id] = msg
            }
            if let raw = (b["encounterDateTimestamp"] as? NSNumber)?.doubleValue {
                let (date, wrongUnits) = BondBackend.encounterDate(fromTimestamp: raw)
                if store.encounters[id] != date { store.setNextMeeting(date, for: id) }
                // Repair a date an earlier build stored in milliseconds (the original app
                // showed it as millions of days away).
                if wrongUnits, let date {
                    Task { try? await BondBackend.updateEncounter(id, date: date, bearer: token) }
                }
            }

            // Received touches. New ones go to the history, play on the bracelet (except on
            // the very first sync after login, which only records what is already there),
            // and are acknowledged so the sender sees them delivered.
            let incomingTouches = (b["touches"] as? [[String: Any]]) ?? []
            if !firstSync, !incomingTouches.filter({ !seen.contains(($0["id"] as? String) ?? "") }).isEmpty {
                let n = incomingTouches.filter { !seen.contains(($0["id"] as? String) ?? "") }.count
                NetLog.shared.log(.recv, "Received \(n) touch(es) ← \(bond.partnerName) (original Bond API)")
            }
            for t in incomingTouches {
                guard let touchId = t["id"] as? String, !seen.contains(touchId) else { continue }
                seen.insert(touchId)
                let msg = (t["message"] as? [String: Any]) ?? [:]
                let ms = (msg["timestamp"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
                // `meaning` is the id of the saved meaning the server matched (not its name).
                let meaningRef = BondBackend.meaningRef(t["meaning"])
                let meaning = meaningRef.flatMap { ref in meanings.first { $0.serverID == ref } }
                let touch = TouchMessage(id: TouchMessage.stableID(from: touchId), bondID: id,
                                         senderID: (b["firebaseId"] as? String) ?? id,
                                         pattern: BondBackend.pattern(msg["pattern"]),
                                         generation: BondBackend.generation(msg["generation"]),
                                         colorRGB: meaning?.colorRGB ?? color,
                                         endColorRGB: meaning?.endColorRGB ?? color,
                                         sentAt: Date(timeIntervalSince1970: ms / 1000),
                                         meaningLabel: meaning?.label,
                                         meaningEmoji: meaning?.emoji)
                newTouches.append(touch)
                if !firstSync, id == selectedPartnerID, !store.doNotDisturb { feel(touch) }
                toAck.append((id, touchId))
            }
        }

        recordTouches(newTouches)
        legacyPartners = partners
        autoLinkPartners()
        legacyPending = pending
        incomingInvites = incoming
        seenTouchIDs = seen
        legacyPrimed = true
        if selectedPartnerID == nil || !self.partners.contains(where: { $0.id == selectedPartnerID }) {
            selectedPartnerID = self.partners.first?.id
        }
        for ack in toAck {
            try? await BondBackend.ackTouch(bondId: ack.bondId, touchId: ack.touchId, bearer: token)
        }
    }

    /// Partner location / sharing from `GET bond/api/v3/bonds/details`.
    private func legacyRefreshDetails(token: String) async {
        guard let details = try? await BondBackend.getPartnersDetails(bearer: token) else { return }
        for d in details {
            guard let id = d["bondId"] as? String,
                  let i = legacyPartners.firstIndex(where: { $0.id == id }) else { continue }
            let loc = d["location"] as? [String: Any]
            if (d["sharing"] as? Bool) == true,
               let lat = (loc?["lat"] as? NSNumber)?.doubleValue,
               let lng = (loc?["lng"] as? NSNumber)?.doubleValue {
                legacyPartners[i].latitude = lat
                legacyPartners[i].longitude = lng
            } else {
                legacyPartners[i].latitude = nil
                legacyPartners[i].longitude = nil
            }
            // The original app shares the partner's phone battery here (a fraction or a percent).
            if let raw = (d["battery"] as? NSNumber)?.doubleValue, raw >= 0 {
                var p = legacyPartners[i].presence ?? PresenceInfo(online: legacyPartners[i].online)
                p.phoneBattery = raw > 1 ? min(raw / 100, 1) : raw
                legacyPartners[i].presence = p
            }
        }
    }

    // MARK: - Presence

    func legacySetOnline(_ online: Bool) async {
        guard legacySignedIn, hasOriginalOnlyPartners, let token = try? await legacyToken(),
              let status = try? await BondBackend.setOnline(online, bearer: token) else { return }
        for i in legacyPartners.indices {
            if let on = status[legacyPartners[i].id] {
                if legacyPartners[i].online && !on { legacyPartners[i].lastSeen = Date() }
                legacyPartners[i].online = on
            }
        }
    }

    func legacySetSharing(_ on: Bool) async {
        guard legacySignedIn, hasOriginalOnlyPartners, let token = try? await legacyToken() else { return }
        try? await BondBackend.updateSharing(on, bearer: token)
    }

    /// Pushes the user's location, at most every 30 seconds.
    func legacyPushLocation(_ coord: CLLocationCoordinate2D) async {
        guard legacySignedIn, hasOriginalOnlyPartners, Date().timeIntervalSince(legacyLastLocationPush) > 30,
              let token = try? await legacyToken() else { return }
        legacyLastLocationPush = Date()
        try? await BondBackend.updateLocation(lat: coord.latitude, lng: coord.longitude, bearer: token)
    }

    // MARK: - Touches

    /// Sends a raw touch; returns the saved meaning the server matched it to, if any.
    @discardableResult
    func legacySendTouch(_ touch: TouchMessage, bond: Bond) async throws -> TouchMeaning? {
        let token = try await legacyToken()
        let result = try await BondBackend.sendTouch(bondId: bond.id, pattern: touch.pattern,
                                                     generation: touch.generation, bearer: token)
        guard let ref = result.meaningID else { return nil }
        return meanings(for: bond).first { $0.serverID == ref }
    }

    // MARK: - Bonds / invites

    /// Invites an original-app user by their account email.
    func legacyInvite(email: String) async throws {
        let token = try await legacyToken()
        try await BondBackend.createBond(email: email.trimmingCharacters(in: .whitespaces), bearer: token)
        await legacySyncOnce()
    }

    func legacyAccept(_ bond: Bond) async {
        do {
            let token = try await legacyToken()
            try await BondBackend.acceptBond(bond.id, bearer: token)
            selectedPartnerID = bond.id
            await legacySyncOnce()
        } catch {
            statusLine = "Couldn't accept: \(error.localizedDescription)"
        }
    }

    /// Unbonds, cancels a sent invite, or declines a received one.
    func legacyCancelBond(_ bond: Bond) async {
        do {
            let token = try await legacyToken()
            try await BondBackend.cancelBond(bond.id, bearer: token)
            legacyPartners.removeAll { $0.id == bond.id }
            legacyPending.removeAll { $0.id == bond.id }
            incomingInvites.removeAll { $0.id == bond.id }
            if selectedPartnerID == bond.id { selectedPartnerID = partners.first?.id }
        } catch {
            statusLine = "Couldn't remove: \(error.localizedDescription)"
        }
    }

    // MARK: - Greeting / encounters

    func setGreeting(_ text: String, for bondID: String?) {
        store.setGreeting(text, for: bondID)
        guard let bond = legacyBond(bondID) else { return }
        Task {
            guard let token = try? await legacyToken() else { return }
            try? await BondBackend.updatePartnerMessage(bond.id, message: text, bearer: token)
        }
    }

    func setNextMeeting(_ date: Date?, for bondID: String?) {
        store.setNextMeeting(date, for: bondID)
        guard let bond = legacyBond(bondID) else { return }
        Task {
            guard let token = try? await legacyToken() else { return }
            try? await BondBackend.updateEncounter(bond.id, date: date, bearer: token)
        }
    }

    /// Your colour for a partner (original backend: `PUT bonds/{id}/settings`).
    func setPartnerColor(_ rgb: Int, for bondID: String) {
        if let i = legacyPartners.firstIndex(where: { $0.id == bondID }) {
            legacyPartners[i].colorRGB = rgb
            let icon = legacyPartnerIcons[bondID] ?? ""
            Task {
                guard let token = try? await legacyToken() else { return }
                try? await BondBackend.updatePartnerSettings(bondID, colorRGB: rgb, icon: icon, bearer: token)
            }
        } else if let i = cloudPartners.firstIndex(where: { $0.id == bondID }) {
            cloudPartners[i].colorRGB = rgb
        }
    }

    private func legacyBond(_ id: String?) -> Bond? {
        guard let id else { return nil }
        return legacyPartners.first { $0.id == id }?.bond
    }

    // MARK: - Touch Language

    /// The selected partner's Touch Language: the server's for an original-app partner,
    /// the local library for an iCloud partner.
    var currentMeanings: [TouchMeaning] {
        if let bond = selectedPartner?.bond, bond.legacy { return legacyMeanings[bond.id] ?? [] }
        return store.meanings
    }

    /// A bond's Touch Language: the server's for an original-app partner, the local library
    /// for an iCloud partner.
    func meanings(for bond: Bond) -> [TouchMeaning] {
        bond.legacy ? (legacyMeanings[bond.id] ?? []) : store.meanings
    }

    /// The saved meaning a touch closely matches, if any — so a touch that's really
    /// "Love you" (made on the screen, the bracelet or the watch) is treated as it.
    func matchingMeaning(pattern: [Int], generation: Int, in list: [TouchMeaning]) -> TouchMeaning? {
        var best: (TouchMeaning, Double)?
        for m in list where !m.pattern.isEmpty {
            let score = TouchPattern.matchScore(pattern, generation: generation, m.pattern, generation: m.touchGeneration)
            if score >= TouchPattern.matchThreshold(generation, m.touchGeneration), score > (best?.1 ?? 0) {
                best = (m, score)
            }
        }
        return best?.0
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
        guard let bond = selectedPartner?.bond, bond.legacy else { store.meanings.append(meaning); return }
        do {
            let token = try await legacyToken()
            let id = try await BondBackend.createMeaning(bondId: bond.id, meaning, bearer: token)
            var saved = meaning
            saved.serverID = id
            legacyMeanings[bond.id, default: []].append(saved)
        } catch {
            statusLine = "Couldn't save touch: \(error.localizedDescription)"
        }
    }

    func deleteMeaning(_ meaning: TouchMeaning) async {
        guard let bond = selectedPartner?.bond, bond.legacy, let serverID = meaning.serverID else {
            store.meanings.removeAll { $0.id == meaning.id }
            return
        }
        do {
            let token = try await legacyToken()
            try await BondBackend.deleteMeaning(bondId: bond.id, meaningId: serverID, bearer: token)
            legacyMeanings[bond.id]?.removeAll { $0.serverID == serverID }
        } catch {
            statusLine = "Couldn't delete touch: \(error.localizedDescription)"
        }
    }

    // MARK: - Profile

    /// Pushes name + colour to the account, debounced (the colour picker fires per change).
    func legacyPublishProfile(name: String, colorRGB: Int) {
        guard legacySignedIn, hasOriginalOnlyPartners else { return }
        legacyProfileTask?.cancel()
        legacyProfileTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self, let token = try? await self.legacyToken() else { return }
            try? await BondBackend.updateProfile(name: name, colorRGB: colorRGB, bearer: token)
        }
    }
}
