import CloudKit
import Combine
import Foundation
import SwiftUI

/// Ties the iCloud relay, the bracelet, HealthKit, and local storage together, and owns
/// the app state the views render. Supports multiple partners.
@MainActor
final class AppModel: ObservableObject {
    @Published var partners: [Partner] = []
    /// Invites the user created that no partner has accepted yet (not active partners).
    @Published var pendingBonds: [Bond] = []
    @Published var selectedPartnerID: String?
    @Published var history: [TouchMessage] = []                  // sent + received touches
    @Published var messagesByBond: [String: [ChatMessage]] = [:] // chat per bond
    @Published var statusLine: String = "Starting…"
    @Published var pendingShare: CKShare?
    @Published var braceletState: BraceletState = .disconnected
    @Published var partnerHeartbeatActive = false
    @Published var sharingHeartbeat = false
    @Published private(set) var myUserID: String = ""
    @Published private(set) var ready = false

    let bracelet = BraceletManager()
    let store = LocalStore()
    let heart = HeartRateService()
    private let relay = CloudRelay()

    var selectedPartner: Partner? { partners.first { $0.id == selectedPartnerID } }
    var activeBond: Bond? { selectedPartner?.bond }

    init() {
        bracelet.$state.receive(on: DispatchQueue.main).assign(to: &$braceletState)
        bracelet.$heartbeatActive.receive(on: DispatchQueue.main).assign(to: &$partnerHeartbeatActive)
        heart.onBPM = { [weak self] bpm in Task { @MainActor in await self?.relayHeartbeat(bpm) } }
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard await relay.accountIsAvailable() else {
            statusLine = "Sign in to iCloud to use Bond Touch Beyond."
            return
        }
        do {
            myUserID = try await relay.currentUserID()
            let bonds = try await relay.loadBonds()
            partners = bonds.filter { !$0.pending }.map { Partner(bond: $0) }
            pendingBonds = bonds.filter { $0.pending }
            if selectedPartnerID == nil { selectedPartnerID = partners.first?.id }
            ready = true
            statusLine = "Ready."
            bracelet.startScanning()
            await publishProfile()
            await setOnline(true)
            await refreshAll()
        } catch {
            statusLine = "iCloud error: \(error.localizedDescription)"
        }
    }

    func setOnline(_ online: Bool) async {
        for partner in partners {
            try? await relay.sendPresence(online: online, bond: partner.bond, senderID: myUserID)
        }
    }

    // MARK: - Partners

    func createBond() async {
        do {
            let (bond, share) = try await relay.createBond(displayName: store.profile.name.isEmpty ? "Me" : store.profile.name)
            // A created invite is pending until the partner accepts — it is not a partner yet.
            pendingBonds.append(bond)
            pendingShare = share
        } catch {
            statusLine = "Couldn't create bond: \(error.localizedDescription)"
        }
    }

    /// Removes a partner or cancels a pending invite, deleting its CloudKit zone.
    func removeBond(_ bond: Bond) async {
        do {
            try await relay.deleteBond(bond)
            partners.removeAll { $0.id == bond.id }
            pendingBonds.removeAll { $0.id == bond.id }
            if selectedPartnerID == bond.id { selectedPartnerID = partners.first?.id }
        } catch {
            statusLine = "Couldn't remove: \(error.localizedDescription)"
        }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            let bond = try await relay.acceptShare(metadata)
            if !partners.contains(where: { $0.id == bond.id }) {
                partners.append(Partner(bond: bond))
            }
            selectedPartnerID = bond.id
            await publishProfile()
            await refreshAll()
        } catch {
            statusLine = "Couldn't join bond: \(error.localizedDescription)"
        }
    }

    // MARK: - Sending

    func sendTouch(pattern: [Int], colorRGB: Int, endColorRGB: Int? = nil, toBondID: String? = nil) async {
        guard let bond = bond(for: toBondID) else { return }
        let touch = TouchMessage(senderID: myUserID, pattern: pattern,
                                 colorRGB: colorRGB, endColorRGB: endColorRGB)
        do {
            try await relay.sendTouch(touch, bond: bond)
            history.append(touch)
        } catch { statusLine = "Send failed: \(error.localizedDescription)" }
    }

    func sendChatText(_ text: String, toBondID: String? = nil) async {
        guard let bond = bond(for: toBondID), !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let msg = ChatMessage(bondID: bond.id, senderID: myUserID, kind: .text, text: text)
        do {
            try await relay.sendChat(msg, bond: bond)
            messagesByBond[bond.id, default: []].append(msg)
        } catch { statusLine = "Message failed: \(error.localizedDescription)" }
    }

    private func bond(for id: String?) -> Bond? {
        if let id { return partners.first { $0.id == id }?.bond }
        return activeBond
    }

    // MARK: - Profile

    func publishProfile() async {
        let p = store.profile
        guard p.isComplete else { return }
        for partner in partners {
            try? await relay.sendProfile(name: p.name, colorRGB: p.colorRGB, bond: partner.bond, senderID: myUserID)
        }
    }

    // MARK: - Receiving

    func handleRemoteNotification() async { await refreshAll() }

    func refreshAll() async {
        for index in partners.indices {
            let partner = partners[index]
            guard let events = try? await relay.fetchNewEvents(bond: partner.bond, myUserID: myUserID) else { continue }
            history.append(contentsOf: events.touches)
            if !events.messages.isEmpty {
                messagesByBond[partner.id, default: []].append(contentsOf: events.messages)
            }
            if let name = events.partnerName { partners[index].displayName = name }
            if let color = events.partnerColorRGB { partners[index].colorRGB = color }
            if let online = events.presenceOnline { partners[index].online = online }
            if let seen = events.presenceLastSeen { partners[index].lastSeen = seen }

            // Only the selected partner's touches/heartbeat drive the bracelet.
            if partner.id == selectedPartnerID, !store.doNotDisturb {
                for touch in events.touches { bracelet.play(touch) }
                if let bpm = events.latestBPM { bracelet.startHeartbeat(bpm: bpm) }
            }
        }
    }

    // MARK: - Heartbeat sharing

    func startSharingHeartbeat() async {
        await heart.requestAuthorization()
        guard heart.authorized else {
            statusLine = "Allow heart-rate access in Health to share your heartbeat."
            return
        }
        heart.start()
        sharingHeartbeat = true
    }

    func stopSharingHeartbeat() {
        heart.stop()
        sharingHeartbeat = false
    }

    private func relayHeartbeat(_ bpm: Int) async {
        guard sharingHeartbeat, let bond = activeBond else { return }
        try? await relay.sendHeartbeat(bpm: bpm, bond: bond, senderID: myUserID)
    }
}
