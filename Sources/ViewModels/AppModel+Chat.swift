import Foundation

/// End-to-end encrypted chat with original-app partners, through the original backend
/// (see `BondChat` and docs/CHAT_PROTOCOL.md). Opt-in: turning it on gives this phone its
/// own Signal identity, so the original app on another phone stops receiving chat.
extension AppModel {
    var legacyChatReady: Bool { legacySignedIn && store.legacyChatEnabled }

    /// Generates and publishes this phone's chat keys, then opens a session with each partner.
    func enableLegacyChat() async {
        legacyChatStatus = "Setting up encrypted chat…"
        do {
            let token = try await legacyToken()
            guard let uid = BondBackend.tokenUID(token) else {
                throw BondBackend.BackendError(message: "Couldn't read your account id; sign in again.")
            }
            try await chat.initKeysIfNeeded(uid: uid, token: token)
            store.legacyChatEnabled = true
            await legacyChatSync(token: token)
            if legacyChatStatus.hasPrefix("Setting up") { legacyChatStatus = "Encrypted chat is on." }
        } catch {
            legacyChatStatus = "Chat setup failed: \(error.localizedDescription)"
        }
    }

    func resetLegacyChat() {
        store.legacyChatEnabled = false
        chat.store.reset()
        for key in ChatArchive.load().keys { messagesByBond.removeValue(forKey: key) }
        ChatArchive.wipe()
        chatSessionAttempts = [:]
        legacyChatStatus = ""
    }

    private func saveLegacyChat() {
        let ids = Set(legacyPartners.map(\.id)).union(ChatArchive.load().keys)
        ChatArchive.save(messagesByBond.filter { ids.contains($0.key) })
    }

    /// Opens a session with a partner (and announces it) unless one exists. Failures are
    /// retried at most once a minute.
    @discardableResult
    func ensureChatSession(_ bondId: String, token: String, force: Bool = false) async -> Bool {
        if chat.store.hasSession(bondId) { return true }
        if !force, let last = chatSessionAttempts[bondId], Date().timeIntervalSince(last) < 60 { return false }
        chatSessionAttempts[bondId] = Date()
        guard let account = legacyPartnerAccounts[bondId] else { return false }
        do {
            try await chat.createSession(bondId: bondId, partnerUID: account.uid,
                                         partnerPhone: account.phone, token: token)
            try await chat.sendNewSession(bondId: bondId, token: token)
            return true
        } catch {
            let name = legacyPartners.first { $0.id == bondId }?.displayName ?? "Partner"
            legacyChatStatus = "\(name): \(error.localizedDescription)"
            return false
        }
    }

    /// Pulls new messages (`GET bond/api/v3/bonds/chat`), acknowledges, decrypts and stores
    /// them, then opens sessions with partners that don't have one yet.
    func legacyChatSync(token: String) async {
        guard let uid = BondBackend.tokenUID(token) else { return }
        if !chatMaintenanceDone {
            chatMaintenanceDone = true
            try? await chat.initKeysIfNeeded(uid: uid, token: token)
            try? await chat.replenishIfNeeded(uid: uid, token: token)
        }
        guard let chats = try? await chat.sync(token: token) else { return }
        var changed = false

        for c in chats {
            guard let bondId = c["bondId"] as? String else { continue }
            let msgs = ((c["chatMessages"] as? [[String: Any]]) ?? []).sorted {
                ((($0["timestamp"] as? NSNumber)?.doubleValue) ?? 0) < ((($1["timestamp"] as? NSNumber)?.doubleValue) ?? 0)
            }
            if let newest = msgs.last?["id"] as? String, !newest.isEmpty {
                await chat.ack(bondId: bondId, messageId: newest, token: token)
            }
            var known = Set((messagesByBond[bondId] ?? []).compactMap(\.serverID))
            let color = legacyPartners.first { $0.id == bondId }?.colorRGB ?? 0xFF4081
            let account = legacyPartnerAccounts[bondId] ?? (uid: "", phone: "")

            for m in msgs {
                guard let id = m["id"] as? String, !known.contains(id) else { continue }
                known.insert(id)
                let type = (m["type"] as? NSNumber)?.intValue ?? Int((m["type"] as? String) ?? "") ?? 1
                let content = (m["content"] as? String) ?? ""
                let ms = (m["timestamp"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
                let at = Date(timeIntervalSince1970: ms / 1000)
                let sender = "partner:" + bondId

                switch type {
                case 1:
                    guard let data = BondChat.decodeBase64(content),
                          let plain = try? chat.decrypt(data, bondId: bondId),
                          let text = String(data: plain, encoding: .utf8) else { continue }
                    messagesByBond[bondId, default: []].append(
                        ChatMessage(bondID: bondId, senderID: sender, kind: .text, text: text,
                                    colorRGB: color, sentAt: at, serverID: id))
                    changed = true
                case 6:
                    // NewSession: decrypting it sets up the partner's new session; the text is discarded.
                    if let data = BondChat.decodeBase64(content) { _ = try? chat.decrypt(data, bondId: bondId) }
                case 2, 3:
                    guard let image = try? await chat.receiveImage(
                            named: content, secret: type == 3, bondId: bondId,
                            partnerUID: account.uid, partnerPhone: account.phone, token: token),
                          let file = ChatArchive.saveImage(image) else { continue }
                    messagesByBond[bondId, default: []].append(
                        ChatMessage(bondID: bondId, senderID: sender, kind: .image,
                                    colorRGB: color, sentAt: at, serverID: id, imageFile: file))
                    changed = true
                case 4:
                    let before = messagesByBond[bondId]?.count ?? 0
                    messagesByBond[bondId]?.removeAll { $0.serverID == content || $0.serverID == id }
                    changed = changed || (messagesByBond[bondId]?.count ?? 0) != before
                default:
                    continue
                }
            }
        }
        if changed { saveLegacyChat() }

        for p in legacyPartners where !chat.store.hasSession(p.id) {
            await ensureChatSession(p.id, token: token)
        }
    }

    // MARK: - Sending

    func legacySendChat(_ text: String, bond: Bond) async {
        guard legacyChatReady else { statusLine = "Turn on encrypted chat first."; return }
        do {
            let token = try await legacyToken()
            guard await ensureChatSession(bond.id, token: token, force: true) else { return }
            let sent = try await chat.sendText(text, bondId: bond.id, token: token)
            messagesByBond[bond.id, default: []].append(
                ChatMessage(bondID: bond.id, senderID: ChatMessage.legacySelf, kind: .text, text: text,
                            colorRGB: store.profile.colorRGB, sentAt: sent.timestamp, serverID: sent.id))
            saveLegacyChat()
        } catch {
            statusLine = "Message failed: \(error.localizedDescription)"
            legacyChatStatus = statusLine
        }
    }

    /// Sends a photo (JPEG) to an original-app partner.
    func sendChatImage(_ jpeg: Data, toBondID bondID: String? = nil) async {
        let target = bondID.flatMap { id in partners.first { $0.id == id } } ?? selectedPartner
        guard let bond = target?.bond, bond.legacy, legacyChatReady else {
            statusLine = "Photos are available with original-app partners once encrypted chat is on."
            return
        }
        do {
            let token = try await legacyToken()
            guard let uid = BondBackend.tokenUID(token),
                  await ensureChatSession(bond.id, token: token, force: true) else { return }
            let (sent, _) = try await chat.sendImage(jpeg, secret: false, bondId: bond.id, uid: uid, token: token)
            let file = ChatArchive.saveImage(jpeg)
            messagesByBond[bond.id, default: []].append(
                ChatMessage(bondID: bond.id, senderID: ChatMessage.legacySelf, kind: .image,
                            colorRGB: store.profile.colorRGB, sentAt: sent.timestamp,
                            serverID: sent.id, imageFile: file))
            saveLegacyChat()
        } catch {
            statusLine = "Photo failed: \(error.localizedDescription)"
            legacyChatStatus = statusLine
        }
    }

    /// Marks the newest received message as seen (`PUT …/chatmessages/{id}/seen`).
    func markLegacyChatSeen(_ bondID: String) async {
        guard legacyChatReady,
              let last = messagesByBond[bondID]?.last(where: { $0.senderID != ChatMessage.legacySelf }),
              let id = last.serverID, let token = try? await legacyToken() else { return }
        await chat.markSeen(bondId: bondID, messageId: id, token: token)
    }
}
