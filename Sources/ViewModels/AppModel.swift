import CloudKit
import Combine
import CoreLocation
import Foundation
import SwiftUI
import UIKit

/// Ties the iCloud relay, the bracelet, HealthKit, and local storage together, and owns
/// the app state the views render. Supports multiple partners.
@MainActor
final class AppModel: ObservableObject {
    /// Partners bonded over iCloud (CloudKit shared zones).
    @Published var cloudPartners: [Partner] = []
    /// iCloud invites the user created that no partner has accepted yet.
    @Published var cloudPending: [Bond] = []

    // Original Bond Touch backend (runs in parallel with iCloud; see AppModel+Legacy).
    @Published var legacyPartners: [Partner] = []
    @Published var legacyPending: [Bond] = []
    /// Bond invites other original-app users sent to this account (accept / decline).
    @Published var incomingInvites: [Bond] = []
    /// Touch Language per original-app bond, as stored on the server.
    @Published var legacyMeanings: [String: [TouchMeaning]] = [:]
    @Published var legacyStatus = "Not signed in"
    @Published var legacyLastSync: Date?
    var legacyTask: Task<Void, Never>?
    var legacyProfileTask: Task<Void, Never>?
    var legacyPrimed = false
    var legacyCycle = 0
    var legacyLastLocationPush = Date.distantPast

    // Encrypted chat with original-app partners (see AppModel+Chat).
    let chat = BondChat()
    /// Partner Firebase UID + legacy phone number per bond, for their key files and photos.
    var legacyPartnerAccounts: [String: (uid: String, phone: String)] = [:]
    var chatSessionAttempts: [String: Date] = [:]
    /// Partner icon from the bond's settings (kept when updating the colour).
    var legacyPartnerIcons: [String: String] = [:]
    var chatMaintenanceDone = false
    @Published var legacyChatStatus = ""

    // Profile photos (see AppModel+Photos).
    @Published var partnerPhotos: [String: UIImage] = [:]
    @Published var myPhoto: UIImage?
    var photoRequests: Set<String> = []
    /// The Apple Watch link (touch bar + meanings on the watch).
    let watch = WatchBridge()
    /// Repairs a bracelet stuck in firmware-update mode.
    let recovery = FirmwareRecovery()
    /// Keeps the app running in the background for original-app partners.
    let keeper = BackgroundKeeper()

    /// Every partner, once each: iCloud partners, plus original-app partners who aren't on
    /// iCloud with you yet. A partner who has moved to iCloud is shown (and synced) only
    /// through their iCloud bond.
    var partners: [Partner] {
        let migrated = migratedLegacyIDs
        return cloudPartners + legacyPartners.filter { !migrated.contains($0.id) }
    }
    /// Every invite the user sent that has not been accepted yet.
    var pendingBonds: [Bond] { cloudPending + legacyPending }
    @Published var selectedPartnerID: String?
    @Published var history: [TouchMessage] = []                  // sent + received touches
    @Published var messagesByBond: [String: [ChatMessage]] = [:] // chat per bond
    @Published var statusLine: String = "Starting…"
    @Published var pendingShareRoot: CKRecord?
    @Published var braceletState: BraceletState = .disconnected
    @Published var partnerHeartbeatActive = false
    /// True for the 10 s while the user's own heartbeat is being sent.
    @Published var sendingHeartbeat = false
    @Published private(set) var myUserID: String = ""
    @Published private(set) var ready = false

    let bracelet = BraceletManager()
    let store = LocalStore()
    let heart = HeartRateService()
    let location = LocationService()
    let relay = CloudRelay()

    @Published var sharingLocation = false

    var selectedPartner: Partner? { partners.first { $0.id == selectedPartnerID } }
    var activeBond: Bond? { selectedPartner?.bond }

    init() {
        messagesByBond = ChatArchive.load()
        bracelet.$state.receive(on: DispatchQueue.main).assign(to: &$braceletState)
        bracelet.$heartbeatActive.receive(on: DispatchQueue.main).assign(to: &$partnerHeartbeatActive)
        location.onUpdate = { [weak self] coord in Task { @MainActor in await self?.broadcastLocation(coord) } }
        // A tap pattern made on the user's own bracelet is a touch for the selected partner.
        bracelet.onLocalTap = { [weak self] pattern, generation in
            Task { @MainActor in
                guard let self else { return }
                await self.sendTouch(pattern: pattern, generation: generation,
                                     colorRGB: self.store.profile.colorRGB)
            }
        }
        watch.start(self)
        recovery.start(bracelet)
    }

    /// Whether the app needs to keep running in the background: on in Settings and some
    /// partner is on the original servers (iCloud partners wake the app with pushes).
    var needsBackgroundKeepAlive: Bool {
        store.keepAliveInBackground && legacySignedIn && hasOriginalOnlyPartners
    }

    func updateKeepAlive() {
        if needsBackgroundKeepAlive { keeper.start() } else { keeper.stop() }
    }

    // MARK: - Presence (live location)

    func setLocationSharing(_ on: Bool) {
        sharingLocation = on
        Task { await legacySetSharing(on) }
        if on {
            location.start()
        } else {
            location.stop()
            Task { await setOnline(true) }   // keep presence, drop the shared coordinates
        }
    }

    private func broadcastLocation(_ coord: CLLocationCoordinate2D) async {
        guard sharingLocation else { return }
        await legacyPushLocation(coord)
        for partner in cloudPartners {
            try? await relay.sendPresence(online: true, bond: partner.bond, senderID: myUserID,
                                          latitude: coord.latitude, longitude: coord.longitude)
        }
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        loadMyPhoto()
        bracelet.startScanning()
        // The original backend works without iCloud, so start it first and independently.
        startLegacySync()
        guard await relay.accountIsAvailable() else {
            statusLine = "Sign in to iCloud to use Bond Touch Beyond."
            return
        }
        do {
            myUserID = try await relay.currentUserID()
            let bonds = try await relay.loadBonds()
            cloudPartners = bonds.filter { !$0.pending }.map { Partner(bond: $0) }
            cloudPartners.forEach { loadCachedPhoto(bondID: $0.id) }
            cloudPending = bonds.filter { $0.pending }
            if selectedPartnerID == nil { selectedPartnerID = partners.first?.id }
            ready = true
            statusLine = "Ready."
            await publishProfile()
            await setOnline(true)
            await refreshAll()
        } catch {
            statusLine = "iCloud error: \(error.localizedDescription)"
        }
    }

    /// Foreground / background: presence on both backends, and the original backend's
    /// sync loop runs only while the app is active.
    func setActive(_ active: Bool) async {
        if active {
            updateKeepAlive()
            startLegacySync()
            await legacySetOnline(true)
            await setOnline(true)
            await refreshAll()
        } else if keeper.running {
            // Kept alive in the background: keep syncing and stay online.
        } else {
            stopLegacySync()
            await legacySetOnline(false)
            await setOnline(false)
        }
    }

    func setOnline(_ online: Bool) async {
        for partner in cloudPartners {
            try? await relay.sendPresence(online: online, bond: partner.bond, senderID: myUserID)
        }
    }

    // MARK: - Partners

    func createBond() async {
        do {
            let (bond, root) = try await relay.createBond(displayName: store.profile.name.isEmpty ? "Me" : store.profile.name)
            // A created invite is pending until the partner accepts — it is not a partner yet.
            cloudPending.append(bond)
            pendingShareRoot = root
        } catch {
            statusLine = "Couldn't create bond: \(error.localizedDescription)"
        }
    }

    /// Removes a partner or cancels a pending invite, deleting its CloudKit zone.
    func removeBond(_ bond: Bond) async {
        if bond.legacy { await legacyCancelBond(bond); return }
        do {
            try await relay.deleteBond(bond)
            cloudPartners.removeAll { $0.id == bond.id }
            cloudPending.removeAll { $0.id == bond.id }
            if selectedPartnerID == bond.id { selectedPartnerID = partners.first?.id }
        } catch {
            statusLine = "Couldn't remove: \(error.localizedDescription)"
        }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            let bond = try await relay.acceptShare(metadata)
            if !cloudPartners.contains(where: { $0.id == bond.id }) {
                cloudPartners.append(Partner(bond: bond))
            }
            selectedPartnerID = bond.id
            await publishProfile()
            await refreshAll()
        } catch {
            statusLine = "Couldn't join bond: \(error.localizedDescription)"
        }
    }

    // MARK: - Sending

    func sendTouch(pattern: [Int], generation: Int = 2, colorRGB: Int, endColorRGB: Int? = nil,
                   toBondID: String? = nil) async {
        guard let bond = bond(for: toBondID) else { return }
        // Finish sending even if the app goes to the background meanwhile (e.g. a touch
        // made on the bracelet while the phone is locked).
        let bg = UIApplication.shared.beginBackgroundTask(withName: "send-touch")
        defer { UIApplication.shared.endBackgroundTask(bg) }
        let touch = TouchMessage(senderID: myUserID, pattern: pattern, generation: generation,
                                 colorRGB: colorRGB, endColorRGB: endColorRGB)
        do {
            if bond.legacy {
                try await legacySendTouch(touch, bond: bond)
            } else {
                try await relay.sendTouch(touch, bond: bond)
            }
            history.append(touch)
        } catch { statusLine = "Send failed: \(error.localizedDescription)" }
    }

    private func bond(for id: String?) -> Bond? {
        if let id { return partners.first { $0.id == id }?.bond }
        return activeBond
    }

    // MARK: - Profile

    func publishProfile() async {
        let p = store.profile
        guard p.isComplete else { return }
        legacyPublishProfile(name: p.name, colorRGB: p.colorRGB)
        for partner in cloudPartners {
            try? await relay.sendProfile(name: p.name, colorRGB: p.colorRGB, photo: myPhotoFileURL,
                                         bond: partner.bond, senderID: myUserID)
        }
    }

    // MARK: - Receiving

    func handleRemoteNotification() async { await refreshAll() }

    func refreshAll() async {
        defer { autoLinkPartners() }
        for index in cloudPartners.indices {
            let partner = cloudPartners[index]
            guard let events = try? await relay.fetchNewEvents(bond: partner.bond, myUserID: myUserID) else { continue }
            guard index < cloudPartners.count, cloudPartners[index].id == partner.id else { continue }
            history.append(contentsOf: events.touches)
            if !events.messages.isEmpty {
                appendChat(events.messages, bondID: partner.id)
            }
            if let name = events.partnerName { cloudPartners[index].displayName = name }
            if let color = events.partnerColorRGB { cloudPartners[index].colorRGB = color }
            if let photo = events.partnerPhoto { setPartnerPhoto(photo, bondID: partner.id) }
            if let online = events.presenceOnline { cloudPartners[index].online = online }
            if let seen = events.presenceLastSeen { cloudPartners[index].lastSeen = seen }
            if let lat = events.presenceLat, let lng = events.presenceLng {
                cloudPartners[index].latitude = lat
                cloudPartners[index].longitude = lng
            }

            // Only the selected partner's touches/heartbeat drive the bracelet.
            if partner.id == selectedPartnerID, !store.doNotDisturb {
                for touch in events.touches { bracelet.play(touch) }
                // A heartbeat plays once, for 10 s — and only if it's fresh (not one that was
                // sent long ago and is only now being fetched).
                if let bpm = events.latestBPM, let at = events.latestBPMAt,
                   Date().timeIntervalSince(at) < 60 {
                    bracelet.playHeartbeat(bpm: bpm)
                }
            }
        }
    }

    // MARK: - Heartbeat (a button press sends 10 s of your heartbeat)

    /// Sends the user's current heartbeat to the selected partner, once: their bracelet
    /// beats at that rate for 10 seconds. iCloud partners get a heartbeat record; a partner
    /// on the original app gets it as a touch in the same rhythm.
    /// Returns the BPM sent, or nil (with `statusLine` explaining why) when it couldn't.
    @discardableResult
    func sendHeartbeat() async -> Int? {
        guard let bond = activeBond else { statusLine = "Choose a partner first."; return nil }
        await heart.requestAuthorization()
        guard heart.authorized else {
            statusLine = "Allow heart-rate access in Health to send your heartbeat."
            return nil
        }
        guard let bpm = await heart.latestBPM() else {
            statusLine = "No recent heart rate. Wear your Apple Watch, then try again."
            return nil
        }
        sendingHeartbeat = true
        defer { Task { @MainActor in try? await Task.sleep(nanoseconds: 10_000_000_000); self.sendingHeartbeat = false } }
        if bond.legacy {
            // 10 s of beats as an on/off pattern: a 120 ms press per beat.
            let period = 60_000 / max(bpm, 30)
            let beats = max(1, 10_000 / period)
            var pattern: [Int] = []
            for i in 0..<beats { pattern.append(120); if i < beats - 1 { pattern.append(max(period - 120, 80)) } }
            await sendTouch(pattern: pattern, generation: 2, colorRGB: 0xE85D75, toBondID: bond.id)
        } else {
            do { try await relay.sendHeartbeat(bpm: bpm, bond: bond, senderID: myUserID) }
            catch { statusLine = "Heartbeat failed: \(error.localizedDescription)"; return nil }
        }
        return bpm
    }
}
