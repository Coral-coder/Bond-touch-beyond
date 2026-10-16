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
            if store.legacyChatEnabled { await legacyChatSync(token: token) }
            legacyCycle += 1
            // Presence and partner details change slowly; refresh them every few cycles.
            if legacyCycle % 4 == 1 { await legacyRefreshDetails(token: token) }
            if legacyCycle % 8 == 1 { await legacySetOnline(true) }
            if legacyCycle == 1 { loadMyPhoto() }
            legacyLastSync = Date()
            legacyStatus = "Synced"
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

            let meanings = ((b["meanings"] as? [[String: Any]]) ?? []).compactMap(BondBackend.meaning(from:))
            legacyMeanings[id] = meanings

            if let msg = b["dashboardMessage"] as? String, !msg.isEmpty, store.greetings[id] != msg {
                store.greetings[id] = msg
            }
            if let ms = (b["encounterDateTimestamp"] as? NSNumber)?.doubleValue {
                let date: Date? = ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : nil
                if store.encounters[id] != date { store.setNextMeeting(date, for: id) }
            }

            // Received touches. New ones go to the history, play on the bracelet (except on
            // the very first sync after login, which only records what is already there),
            // and are acknowledged so the sender sees them delivered.
            for t in (b["touches"] as? [[String: Any]]) ?? [] {
                guard let touchId = t["id"] as? String, !seen.contains(touchId) else { continue }
                seen.insert(touchId)
                let msg = (t["message"] as? [String: Any]) ?? [:]
                let ms = (msg["timestamp"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
                let meaningName = t["meaning"] as? String
                let meaning = meanings.first { $0.label == meaningName }
                let touch = TouchMessage(senderID: (b["firebaseId"] as? String) ?? id,
                                         pattern: BondBackend.pattern(msg["pattern"]),
                                         generation: BondBackend.generation(msg["generation"]),
                                         colorRGB: meaning?.colorRGB ?? color,
                                         endColorRGB: meaning?.endColorRGB ?? color,
                                         sentAt: Date(timeIntervalSince1970: ms / 1000))
                history.append(touch)
                if !firstSync, id == selectedPartnerID, !store.doNotDisturb { bracelet.play(touch) }
                toAck.append((id, touchId))
            }
        }

        history.sort { $0.sentAt < $1.sentAt }
        legacyPartners = partners
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
        }
    }

    // MARK: - Presence

    func legacySetOnline(_ online: Bool) async {
        guard legacySignedIn, let token = try? await legacyToken(),
              let status = try? await BondBackend.setOnline(online, bearer: token) else { return }
        for i in legacyPartners.indices {
            if let on = status[legacyPartners[i].id] {
                if legacyPartners[i].online && !on { legacyPartners[i].lastSeen = Date() }
                legacyPartners[i].online = on
            }
        }
    }

    func legacySetSharing(_ on: Bool) async {
        guard legacySignedIn, let token = try? await legacyToken() else { return }
        try? await BondBackend.updateSharing(on, bearer: token)
    }

    /// Pushes the user's location, at most every 30 seconds.
    func legacyPushLocation(_ coord: CLLocationCoordinate2D) async {
        guard legacySignedIn, Date().timeIntervalSince(legacyLastLocationPush) > 30,
              let token = try? await legacyToken() else { return }
        legacyLastLocationPush = Date()
        try? await BondBackend.updateLocation(lat: coord.latitude, lng: coord.longitude, bearer: token)
    }

    // MARK: - Touches

    func legacySendTouch(_ touch: TouchMessage, bond: Bond) async throws {
        let token = try await legacyToken()
        try await BondBackend.sendTouch(bondId: bond.id, pattern: touch.pattern,
                                        generation: touch.generation, bearer: token)
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
        guard legacySignedIn else { return }
        legacyProfileTask?.cancel()
        legacyProfileTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self, let token = try? await self.legacyToken() else { return }
            try? await BondBackend.updateProfile(name: name, colorRGB: colorRGB, bearer: token)
        }
    }
}
