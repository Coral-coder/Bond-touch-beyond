import CloudKit
import Foundation

/// Chat runs over iCloud for every partner. A partner on the original Bond Touch app is
/// linked to an iCloud bond (invite them, or link one you already share) and chat with them
/// goes through it. History (with photos) is kept on this phone.
///
/// The original backend's own end-to-end chat (`BondChat`) can't be used: its key exchange
/// and photos live in Firebase Storage, which only the official app may access (App Check).
extension AppModel {
    // MARK: - Which iCloud bond carries chat for a partner

    /// The iCloud bond id used for chat with `partnerID`: the partner's own bond for an iCloud
    /// partner, or the linked bond for an original-app partner.
    func chatBondID(for partnerID: String?) -> String? {
        guard let id = partnerID, let partner = partners.first(where: { $0.id == id })
                ?? cloudPartners.first(where: { $0.id == id }) else { return nil }
        if !partner.bond.legacy { return partner.id }
        guard let linked = store.chatLinks[id],
              cloudPartners.contains(where: { $0.id == linked }) || cloudPending.contains(where: { $0.id == linked })
        else { return nil }
        return linked
    }

    private func chatBond(for partnerID: String?) -> Bond? {
        guard let id = chatBondID(for: partnerID) else { return nil }
        return cloudPartners.first { $0.id == id }?.bond ?? cloudPending.first { $0.id == id }
    }

    /// iCloud bonds linked to an original-app partner.
    var chatLinkedCloudIDs: Set<String> { Set(store.chatLinks.values) }

    /// Original-app partners who have joined you on iCloud (their linked iCloud bond is
    /// accepted). They sync through iCloud only.
    var migratedLegacyIDs: Set<String> {
        let accepted = Set(cloudPartners.map(\.id))
        return Set(store.chatLinks.filter { accepted.contains($0.value) }.keys)
    }

    /// Whether any partner still syncs through the original backend only. When none does,
    /// nothing (presence, location, profile) is sent there anymore.
    var hasOriginalOnlyPartners: Bool {
        let migrated = migratedLegacyIDs
        return legacyPartners.contains { !migrated.contains($0.id) }
    }

    /// The iCloud partner that replaces an original-app partner, if they've moved.
    func iCloudPartnerID(forLegacy id: String) -> String? {
        guard migratedLegacyIDs.contains(id) else { return nil }
        return store.chatLinks[id]
    }

    /// Links original-app partners to an iCloud partner with exactly the same name (when
    /// there's just one such), and moves the selection onto the iCloud partner once linked.
    func autoLinkPartners() {
        let linkedCloud = chatLinkedCloudIDs
        for legacy in legacyPartners where store.chatLinks[legacy.id] == nil {
            let name = legacy.displayName.trimmingCharacters(in: .whitespaces).lowercased()
            let matches = cloudPartners.filter {
                !linkedCloud.contains($0.id) && $0.displayName.trimmingCharacters(in: .whitespaces).lowercased() == name
            }
            if matches.count == 1, !name.isEmpty { store.chatLinks[legacy.id] = matches[0].id }
        }
        if let sel = selectedPartnerID, let moved = iCloudPartnerID(forLegacy: sel) {
            selectedPartnerID = moved
        }
        importMeaningsFromMovedPartners()
    }

    /// Once per partner who moved to iCloud: copy their Touch Language from the original
    /// backend into the local library, so nothing is lost.
    private func importMeaningsFromMovedPartners() {
        let key = "ImportedLegacyMeanings"
        var done = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        for id in migratedLegacyIDs where !done.contains(id) {
            guard let list = legacyMeanings[id], let cloudID = store.chatLinks[id] else { continue }
            // Into the library shared with them on iCloud.
            var lib = cloudLibrary(cloudID)
            let existing = Set(lib.filter { $0.deleted != true }.map { $0.label.lowercased() })
            for m in list where !existing.contains(m.label.lowercased()) {
                var copy = m
                copy.serverID = nil
                copy.updatedAt = Date()
                lib.append(copy)
            }
            store.cloudMeanings[cloudID] = lib
            done.insert(id)
        }
        UserDefaults.standard.set(Array(done), forKey: key)
    }

    /// Creates an iCloud bond to invite an original-app partner to chat; it is linked to them
    /// right away and the invite link is offered (`pendingInviteURL`).
    func inviteToICloudChat(_ legacyID: String) async {
        // Replace an earlier, still-unaccepted invite rather than piling them up.
        if let old = store.chatLinks[legacyID], let pending = cloudPending.first(where: { $0.id == old }) {
            await removeBond(pending)
            store.chatLinks.removeValue(forKey: legacyID)
        }
        let before = Set(cloudPending.map(\.id))
        await createBond()
        if let new = cloudPending.first(where: { !before.contains($0.id) }) {
            store.chatLinks[legacyID] = new.id
        }
    }

    /// Links an existing iCloud partner as the chat channel for an original-app partner.
    func linkChat(_ legacyID: String, toCloudBond cloudID: String) {
        store.chatLinks[legacyID] = cloudID
    }

    func unlinkChat(_ legacyID: String) {
        store.chatLinks.removeValue(forKey: legacyID)
    }

    // MARK: - History

    /// Adds messages (deduplicated by id) and saves the history.
    func appendChat(_ messages: [ChatMessage], bondID: String) {
        var list = messagesByBond[bondID] ?? []
        let known = Set(list.map(\.id))
        // Private Space keeps 72 hours — don't bring back older ones a server re-sends.
        let fresh = messages.filter { !known.contains($0.id) && Date().timeIntervalSince($0.sentAt) < ChatArchive.lifetime }
        guard !fresh.isEmpty else { return }
        list += fresh
        list.sort { $0.sentAt < $1.sentAt }
        messagesByBond[bondID] = list
        ChatArchive.save(messagesByBond)
    }

    /// The id of our latest message the partner's phone has received, for a "Seen" under it.
    func lastSeenMessageID(for partnerID: String?) -> UUID? {
        guard let id = chatBondID(for: partnerID), let seen = partnerSeenMessage[id] else { return nil }
        return (messagesByBond[id] ?? []).last { ($0.ringSeq ?? .max) <= seen }?.id
    }

    /// Messages shown for a partner (their chat bond's history).
    func chatMessages(for partnerID: String?) -> [ChatMessage] {
        guard let id = chatBondID(for: partnerID) else { return [] }
        return messagesByBond[id] ?? []
    }

    // MARK: - Sending

    func sendChatText(_ text: String, toBondID: String? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let bond = chatBond(for: toBondID ?? selectedPartnerID) else {
            statusLine = "Invite this partner to iCloud chat first."
            return
        }
        let msg = ChatMessage(bondID: bond.id, senderID: myUserID, kind: .text, text: trimmed,
                              colorRGB: store.profile.colorRGB)
        do {
            var sent = msg
            sent.ringSeq = try await relay.sendChat(msg, bond: bond)
            appendChat([sent], bondID: bond.id)
        } catch {
            statusLine = "Message failed: \(error.localizedDescription)"
        }
    }

    /// Sends a photo (JPEG) over iCloud.
    func sendChatImage(_ jpeg: Data, toBondID: String? = nil) async {
        guard let bond = chatBond(for: toBondID ?? selectedPartnerID) else {
            statusLine = "Invite this partner to iCloud chat first."
            return
        }
        guard let file = ChatArchive.saveImage(jpeg) else { return }
        let msg = ChatMessage(bondID: bond.id, senderID: myUserID, kind: .image,
                              colorRGB: store.profile.colorRGB, imageFile: file)
        do {
            var sent = msg
            sent.ringSeq = try await relay.sendChat(msg, bond: bond)
            appendChat([sent], bondID: bond.id)
        } catch {
            statusLine = "Photo failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Original-backend encrypted chat (disabled: App Check)

    /// Forgets any keys generated by the disabled original-backend chat.
    func resetLegacyChat() {
        store.legacyChatEnabled = false
        chat.store.reset()
        legacyChatStatus = ""
    }
}
