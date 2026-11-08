import CloudKit
import Foundation
import UIKit
import UserNotifications

/// Chat runs over iCloud for every partner. History (with photos) is kept on this phone.
extension AppModel {
    // MARK: - Which iCloud bond carries chat for a partner

    /// The iCloud bond id used for chat with `partnerID` (the partner's own bond).
    func chatBondID(for partnerID: String?) -> String? {
        guard let id = partnerID, let partner = partners.first(where: { $0.id == id })
                ?? cloudPartners.first(where: { $0.id == id }) else { return nil }
        return partner.id
    }

    private func chatBond(for partnerID: String?) -> Bond? {
        guard let id = chatBondID(for: partnerID) else { return nil }
        return cloudPartners.first { $0.id == id }?.bond ?? cloudPending.first { $0.id == id }
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
        if fresh.contains(where: { $0.senderID != myUserID && $0.senderID != ChatMessage.localSelf
                                   && Date().timeIntervalSince($0.sentAt) < 5 * 60 }) {
            notifyBracelet(bondID: bondID)
            notifyChatLocally(bondID: bondID)
        }
    }

    /// A message picked up from iCloud (its push may not have come through): a notification
    /// that never shows what was said. Same id as the push's, so it's never doubled.
    private func notifyChatLocally(bondID: String) {
        guard UIApplication.shared.applicationState != .active, NotificationKind.chat.isOn else { return }
        let content = UNMutableNotificationContent()
        content.title = partners.first { $0.id == bondID }?.displayName ?? "Your partner"
        content.body = "New message in Private Space"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let id = "m-\(BondCrypto.locator(forCode: bondID).prefix(16))"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: - Bracelet notifications

    /// How the bracelet tells you about a new Private Space message, as the original:
    /// General — a quick triple buzz in the partner's colour; Secret — a rainbow sweep that
    /// only you know the meaning of; or off.
    enum BraceletNotify: String, CaseIterable { case off, general, secret }

    static var braceletNotify: BraceletNotify {
        BraceletNotify(rawValue: UserDefaults.standard.string(forKey: "braceletNotifyStyle") ?? "") ?? .general
    }

    /// At most one every 30 seconds; never during Do Not Disturb.
    private func notifyBracelet(bondID: String) {
        let style = Self.braceletNotify
        guard style != .off, !store.quiet() else { return }
        let key = "BraceletNotifiedAt"
        if let last = UserDefaults.standard.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 30 { return }
        UserDefaults.standard.set(Date(), forKey: key)
        let partner = partners.first { $0.id == bondID || chatBondID(for: $0.id) == bondID }
        _ = bracelet.play(Self.notification(style, colorRGB: partner?.colorRGB ?? store.profile.colorRGB),
                          holdIfOffline: false)
    }

    static func notification(_ style: BraceletNotify, colorRGB: Int) -> TouchMessage {
        switch style {
        case .secret:
            // A sweep along the whole bar, red → violet.
            let sweep = (0..<TouchPattern.positions).flatMap { p in [TouchPattern.sample([p]), TouchPattern.sample([p])] }
            return TouchMessage(senderID: "notification", pattern: sweep + sweep.reversed(), generation: 3,
                                colorRGB: 0xFF2A2A, endColorRGB: 0x8A2BE2)
        default:
            return TouchMessage(senderID: "notification", pattern: [90, 90, 90, 90, 90], generation: 2,
                                colorRGB: colorRGB)
        }
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
            statusLine = "Choose a partner first."
            return
        }
        let msg = ChatMessage(bondID: bond.id, senderID: myUserID, kind: .text, text: trimmed,
                              colorRGB: store.profile.colorRGB)
        do {
            var sent = msg
            sent.ringSeq = try await relay.sendChat(msg, bond: bond)
            appendChat([sent], bondID: bond.id)
            await pushChat(bond)
        } catch {
            statusLine = "Message failed: \(error.localizedDescription)"
        }
    }

    /// Sends a photo (JPEG) over iCloud.
    func sendChatImage(_ jpeg: Data, toBondID: String? = nil) async {
        guard let bond = chatBond(for: toBondID ?? selectedPartnerID) else {
            statusLine = "Choose a partner first."
            return
        }
        guard let file = ChatArchive.saveImage(jpeg) else { return }
        let msg = ChatMessage(bondID: bond.id, senderID: myUserID, kind: .image,
                              colorRGB: store.profile.colorRGB, imageFile: file)
        do {
            var sent = msg
            sent.ringSeq = try await relay.sendChat(msg, bond: bond)
            appendChat([sent], bondID: bond.id)
            await pushChat(bond)
        } catch {
            statusLine = "Photo failed: \(error.localizedDescription)"
        }
    }

    /// Wakes the partner's phone so the message arrives now. The notification never shows
    /// what was said — Private Space stays private on a lock screen.
    private func pushChat(_ bond: Bond) async {
        let me = store.profile.name.isEmpty ? "Someone" : store.profile.name
        await pushPartner(bondID: bond.id, title: me, body: "New message in Private Space", group: "m")
    }
}
