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
    /// Polls iCloud bonds every few seconds while the app is foregrounded, so a live
    /// back-and-forth updates without waiting on a silent push (iOS throttles those heavily
    /// in the foreground). Cancelled when the app leaves the foreground — pushes cover that.
    var cloudPollTask: Task<Void, Never>?
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
    /// This device's APNs token (set once iOS registers it), published to partners so they can
    /// wake this phone directly. Each partner's token, by bond, for the same in reverse.
    var myPushToken = ""
    var partnerPushTokens: [String: String] = [:]
    /// Cloud bonds this device has already pushed its profile (incl. photo) to this session.
    var profileSyncedBondIDs: Set<String> = []
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
    private var historyIDs: Set<UUID> = []

    /// Adds touches to the feed, skipping ones already present (the backends re-fetch on
    /// each launch), sorting by time, and saving to disk so the feed survives app updates.
    func recordTouches(_ touches: [TouchMessage]) {
        var added = false
        for t in touches where !historyIDs.contains(t.id) {
            history.append(t)
            historyIDs.insert(t.id)
            added = true
        }
        guard added else { return }
        history.sort { $0.sentAt < $1.sentAt }
        TouchArchive.save(history)
    }

    func recordTouch(_ touch: TouchMessage) { recordTouches([touch]) }
    @Published var messagesByBond: [String: [ChatMessage]] = [:] // chat per bond
    @Published var statusLine: String = "Starting…"
    /// The invite link for a bond just created (share or copy it to the partner).
    @Published var pendingInviteURL: URL?
    @Published var braceletState: BraceletState = .disconnected
    @Published var partnerHeartbeatActive = false
    /// True for the 5 s while the user's own heartbeat is being sent.
    @Published var sendingHeartbeat = false
    @Published private(set) var myUserID: String = ""
    @Published private(set) var ready = false
    /// nil when iCloud is usable; otherwise why it isn't, shown to the user. iCloud features
    /// (pairing, photos, heartbeat relay) need this to be nil; the original backend doesn't.
    @Published var iCloudStatus: String?

    /// Re-checks iCloud and, if it became available, finishes the iCloud setup bootstrap did
    /// not. Call when the app returns to the foreground (the user may have just signed in).
    func refreshICloudStatus() async {
        let msg = await relay.accountStatusMessage()
        iCloudStatus = msg
        if msg == nil, !ready { await bootstrap() }
    }

    let bracelet = BraceletManager()
    /// Vibrates the phone like the bracelet would, when the bracelet isn't connected.
    let haptics = PhoneHaptics()

    /// Plays a partner's touch on the bracelet — or, if the bracelet isn't connected (or the
    /// touch doesn't reach it), on the phone's vibration motor in the same rhythm. In the
    /// background the phone can't run its own vibration, so the touch is held for the
    /// bracelet and the push notification is what buzzes.
    func feel(_ touch: TouchMessage) {
        let foreground = UIApplication.shared.applicationState == .active
        if bracelet.play(touch, holdIfOffline: !foreground) { return }
        if foreground {
            haptics.play(touch)
            NetLog.shared.log(.recv, "Bracelet not connected — played the touch on the phone")
        }
    }

    /// Plays a partner's heartbeat on the bracelet, or lub-dubs the phone if it isn't connected.
    func feelHeartbeat(bpm: Int) {
        bracelet.playHeartbeat(bpm: bpm)       // also drives the on-screen heartbeat
        if !bracelet.isReady { haptics.playHeartbeat(bpm: bpm) }
    }
    let store = LocalStore()
    let heart = HeartRateService()
    let location = LocationService()
    let relay = CloudRelay()

    @Published var sharingLocation = false

    var selectedPartner: Partner? { partners.first { $0.id == selectedPartnerID } }
    var activeBond: Bond? { selectedPartner?.bond }

    init() {
        messagesByBond = ChatArchive.load()
        history = TouchArchive.load()
        historyIDs = Set(history.map { $0.id })
        bracelet.$state.receive(on: DispatchQueue.main).assign(to: &$braceletState)
        bracelet.$heartbeatActive.receive(on: DispatchQueue.main).assign(to: &$partnerHeartbeatActive)
        location.onUpdate = { [weak self] fix in Task { @MainActor in await self?.broadcastLocation(fix) } }
        // A touch made on the user's own bracelet: on a Bond Touch More it's for the partner
        // in the slot it was made in; otherwise for the selected partner.
        bracelet.onLocalTap = { [weak self] pattern, generation, slotBondID in
            Task { @MainActor in
                guard let self else { return }
                let target = slotBondID.flatMap { id in self.partners.contains { $0.id == id } ? id : nil }
                await self.sendTouch(pattern: pattern, generation: generation,
                                     colorRGB: self.store.profile.colorRGB, toBondID: target)
            }
        }
        // The bracelet's partner slots follow the partner list: one slot per partner (up to
        // three), lit in that partner's colour — what the original app sends after pairing.
        Publishers.CombineLatest($cloudPartners, $legacyPartners)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.bracelet.setPartnerMenu(self.partners.map { (id: $0.id, rgb: $0.colorRGB) })
                }
            }
            .store(in: &statusWatch)
        watchStatusForPresence()
        // A touch that didn't make it to the bracelet plays on the phone instead.
        bracelet.onPlayFailed = { [weak self] touch in
            Task { @MainActor in self?.haptics.play(touch) }
        }
        watch.start(self)
        recovery.start(bracelet)
        AppModel.shared = self
    }

    /// A weak reference so the scene delegate can route an accepted CloudKit share invite in.
    static weak var shared: AppModel?

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

    private func broadcastLocation(_ fix: CLLocation) async {
        guard sharingLocation else { return }
        await legacyPushLocation(fix.coordinate)
        await publishPresence(force: false)   // throttled — fixes can arrive every few seconds
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        loadMyPhoto()
        bracelet.startScanning()
        // The original backend works without iCloud, so start it first and independently.
        startLegacySync()
        iCloudStatus = await relay.accountStatusMessage()
        guard iCloudStatus == nil else {
            statusLine = "iCloud is not signed in."
            return
        }
        do {
            myUserID = try await relay.currentUserID()
            let bonds = await relay.loadBonds(roles: store.cloudBondCodes)
            // Forget bonds the inviter has deleted (ones merely unreachable are still listed).
            for code in store.cloudBondCodes.keys where !bonds.contains(where: { $0.id == code }) {
                store.cloudBondCodes[code] = nil
            }
            cloudPartners = bonds.filter { !$0.pending }.map { Partner(bond: $0) }
            cloudPartners.forEach { loadCachedPhoto(bondID: $0.id) }
            cloudPending = bonds.filter { $0.pending }
            if selectedPartnerID == nil { selectedPartnerID = partners.first?.id }
            ready = true
            statusLine = "Ready."
            await publishProfile()
            await setOnline(true)
            await refreshAll()
            startCloudPolling()
            // A join link tapped before the app was ready (cold launch).
            if let code = AppModel.pendingJoinCode {
                AppModel.pendingJoinCode = nil
                await joinBond(code: code)
            }
        } catch {
            statusLine = "iCloud error: \(error.localizedDescription)"
        }
    }

    /// Foreground / background: presence on both backends, and the original backend's
    /// sync loop runs only while the app is active.
    func setActive(_ active: Bool) async {
        if active {
            await refreshICloudStatus()   // the user may have just signed into iCloud
            updateKeepAlive()
            startLegacySync()
            await legacySetOnline(true)
            await setOnline(true)
            await refreshAll()
            startCloudPolling()
        } else if keeper.running {
            // Kept alive in the background: keep syncing and stay online.
            stopCloudPolling()            // cloud bonds wake on push, not a background poll
        } else {
            stopLegacySync()
            stopCloudPolling()
            await legacySetOnline(false)
            await setOnline(false)
        }
    }

    func setOnline(_ online: Bool) async {
        lastOnline = online
        await publishPresence(force: true)
    }

    private var lastOnline = true
    /// Whether each cloud partner's bracelet is connected, from their presence.
    var partnerBraceletConnected: [String: Bool] = [:]
    private var statusWatch = Set<AnyCancellable>()
    private var lastPublished: PresenceInfo?
    private var lastPresencePush = Date.distantPast

    /// This phone's status snapshot for partners: online, shared location + when it was
    /// taken + speed, phone battery/charging, bracelet connected/battery/last connected.
    private func currentPresence() -> PresenceInfo {
        var info = PresenceInfo(online: lastOnline)
        if sharingLocation, let fix = location.lastLocation {
            info.lat = fix.coordinate.latitude
            info.lng = fix.coordinate.longitude
            info.locationAt = fix.timestamp
            info.speed = location.speed
        }
        let device = UIDevice.current
        if device.batteryLevel >= 0 { info.phoneBattery = Double(device.batteryLevel) }
        if device.batteryState != .unknown {
            info.phoneCharging = device.batteryState == .charging || device.batteryState == .full
        }
        info.bracelet = bracelet.isReady
        info.braceletBattery = bracelet.batteryPercent
        info.braceletLastConnected = bracelet.isReady ? Date() : bracelet.lastConnectedAt
        return info
    }

    /// Writes the status snapshot to every iCloud partner. `force: false` (location updates)
    /// is throttled to one every 15 s.
    func publishPresence(force: Bool) async {
        guard !cloudPartners.isEmpty else { return }
        if !force, Date().timeIntervalSince(lastPresencePush) < 15 { return }
        lastPresencePush = Date()
        let info = currentPresence()
        lastPublished = info
        for partner in cloudPartners {
            try? await relay.sendPresence(info, bond: partner.bond)
        }
    }

    /// Republishes when something worth showing changes: the bracelet connects or drops (also
    /// while the phone is locked — the Bluetooth event wakes the app; partners then know
    /// whether to buzz this phone), its battery moves 5 %, the phone's battery moves 5 %, or
    /// the phone is plugged in / unplugged.
    private func watchStatusForPresence() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let center = NotificationCenter.default
        Publishers.MergeMany([
            bracelet.$state.map { _ in () }.eraseToAnyPublisher(),
            bracelet.$batteryPercent.map { _ in () }.eraseToAnyPublisher(),
            center.publisher(for: UIDevice.batteryLevelDidChangeNotification).map { _ in () }.eraseToAnyPublisher(),
            center.publisher(for: UIDevice.batteryStateDidChangeNotification).map { _ in () }.eraseToAnyPublisher(),
        ])
        .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
        .sink { [weak self] in Task { @MainActor in await self?.publishIfStatusChanged() } }
        .store(in: &statusWatch)
    }

    private func publishIfStatusChanged() async {
        guard !cloudPartners.isEmpty else { return }
        let now = currentPresence()
        if let last = lastPublished {
            let bracelet = now.bracelet != last.bracelet
            let braceletBattery = abs((now.braceletBattery ?? -100) - (last.braceletBattery ?? -100)) >= 5
            let phoneBattery = abs((now.phoneBattery ?? -1) - (last.phoneBattery ?? -1)) >= 0.05
            let charging = now.phoneCharging != last.phoneCharging
            guard bracelet || braceletBattery || phoneBattery || charging else { return }
        }
        let task = UIApplication.shared.beginBackgroundTask(withName: "status-presence")
        await publishPresence(force: true)
        UIApplication.shared.endBackgroundTask(task)
    }

    /// Starts polling iCloud bonds while foregrounded (no-op if already running, or if there's
    /// no iCloud partner or open invite). A direct push wakes the app from the background.
    func startCloudPolling() {
        guard cloudPollTask == nil, !cloudPartners.isEmpty || !cloudPending.isEmpty else { return }
        cloudPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { break }
                await self?.refreshAll()
            }
        }
    }

    func stopCloudPolling() {
        cloudPollTask?.cancel()
        cloudPollTask = nil
    }

    // MARK: - Partners

    /// Creates an iCloud bond and its invite link. Returns an error message when it can't
    /// (chiefly: not signed into iCloud), so the UI can show it instead of a dead end.
    @discardableResult
    func createBond() async -> String? {
        iCloudStatus = await relay.accountStatusMessage()
        if let msg = iCloudStatus { return msg }
        if myUserID.isEmpty { myUserID = (try? await relay.currentUserID()) ?? "" }
        do {
            let (bond, url) = try await relay.createBond(
                displayName: store.profile.name.isEmpty ? "Me" : store.profile.name, myUserID: myUserID,
                colorRGB: store.profile.colorRGB, pushToken: myPushToken)
            store.cloudBondCodes[bond.id] = true
            cloudPending.append(bond)
            pendingInviteURL = url
            startCloudPolling()           // notice the moment the partner joins
            return nil
        } catch {
            statusLine = "Couldn't create bond: \(error.localizedDescription)"
            return "Couldn't create the invite: \(error.localizedDescription)"
        }
    }

    /// Joins a bond by its code (typed, or from a tapped invite link).
    @discardableResult
    func joinBond(code rawCode: String) async -> String? {
        let code = CloudRelay.normalize(rawCode)
        if store.cloudBondCodes[code] == true {
            return "That's your own invite code — send it to your partner so they can join."
        }
        if store.cloudBondCodes[code] == false, cloudPartners.contains(where: { $0.id == code }) {
            selectedPartnerID = code      // already paired with this code
            return nil
        }
        iCloudStatus = await relay.accountStatusMessage()
        if let msg = iCloudStatus { return msg }
        if myUserID.isEmpty { myUserID = (try? await relay.currentUserID()) ?? "" }
        do {
            let me = store.profile.name.isEmpty ? "Me" : store.profile.name
            let bond = try await relay.joinBond(code: code, displayName: me,
                                                colorRGB: store.profile.colorRGB, pushToken: myPushToken)
            store.cloudBondCodes[bond.id] = false
            if !cloudPartners.contains(where: { $0.id == bond.id }) { cloudPartners.append(Partner(bond: bond)) }
            cloudPending.removeAll { $0.id == bond.id }
            selectedPartnerID = bond.id
            profileSyncedBondIDs.remove(bond.id)
            await publishProfile()
            await refreshAll()            // picks up the inviter's profile + push token
            startCloudPolling()
            // Tell the inviter straight away (wakes their phone so it sees us join).
            await pushPartner(bondID: bond.id, title: "\(me) connected with you", body: "You're paired 💞")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// A join code from a link tapped while the app was launching, held until ready.
    static var pendingJoinCode: String?

    /// Routes a tapped invite link in. If still starting, the code is joined after bootstrap.
    func handleOpenURL(_ url: URL) {
        guard let code = CloudRelay.code(fromURL: url) else { return }
        if ready { Task { await joinBond(code: code) } }
        else { AppModel.pendingJoinCode = code }
    }

    // MARK: - Sending a touch

    private func bond(for id: String?) -> Bond? {
        if let id { return partners.first { $0.id == id }?.bond }
        return activeBond
    }

    /// Sends a touch to a bond (the selected partner when `toBondID` is nil): iCloud partners
    /// get an encrypted relay record, original-app partners go through the Bond API. Records
    /// it to the local feed either way.
    func sendTouch(pattern: [Int], generation: Int = 2, colorRGB: Int, endColorRGB: Int? = nil,
                   toBondID: String? = nil) async {
        guard let bond = bond(for: toBondID) else { return }
        // Finish sending even if the app goes to the background meanwhile (e.g. a touch
        // made on the bracelet while the phone is locked).
        let bg = UIApplication.shared.beginBackgroundTask(withName: "send-touch")
        defer { UIApplication.shared.endBackgroundTask(bg) }
        let touch = TouchMessage(bondID: bond.id, senderID: myUserID, pattern: pattern, generation: generation,
                                 colorRGB: colorRGB, endColorRGB: endColorRGB)
        let route = bond.legacy ? "original Bond API" : "iCloud"
        NetLog.shared.log(.send, "Send touch → \(bond.partnerName) (\(route))",
                          "gen \(generation), \(pattern.count) samples")
        do {
            if bond.legacy {
                try await legacySendTouch(touch, bond: bond)
            } else {
                try await relay.sendTouch(touch, bond: bond)
                NetLog.shared.log(.ok, "Touch → iCloud accepted", "\(bond.partnerName)")
                // Wake their phone right away (CloudKit's own push can lag in deep sleep).
                let me = store.profile.name.isEmpty ? "Someone" : store.profile.name
                await pushPartner(bondID: bond.id, title: "\(me) touched you", body: "❤️")
            }
            recordTouch(touch)
        } catch {
            statusLine = "Send failed: \(error.localizedDescription)"
            NetLog.shared.log(.fail, "Send touch failed (\(route))", error.localizedDescription)
        }
    }

    /// Sends a saved meaning (Touch Language). For an original-app partner with a server
    /// meaning id it goes through the Bond API (which lights their bracelet by id); otherwise
    /// the meaning's pattern and colour are sent as a normal touch.
    func sendMeaning(_ meaning: TouchMeaning, toBondID: String? = nil) async {
        guard let bond = bond(for: toBondID) else { return }
        if bond.legacy, let serverID = meaning.serverID {
            let bg = UIApplication.shared.beginBackgroundTask(withName: "send-meaning")
            defer { UIApplication.shared.endBackgroundTask(bg) }
            let touch = TouchMessage(bondID: bond.id, senderID: myUserID, pattern: meaning.pattern,
                                     generation: meaning.touchGeneration, colorRGB: meaning.colorRGB,
                                     endColorRGB: meaning.endColorRGB)
            NetLog.shared.log(.send, "Send meaning \"\(meaning.label)\" → \(bond.partnerName) (original Bond API)",
                              "meaningId \(serverID)")
            do {
                try await BondBackend.sendMeaningTouch(bondId: bond.id, meaningId: serverID,
                                                       bearer: try await legacyToken())
                recordTouch(touch)
            } catch {
                statusLine = "Send failed: \(error.localizedDescription)"
                NetLog.shared.log(.fail, "Send meaning failed", error.localizedDescription)
            }
            return
        }
        // iCloud, or a legacy meaning without a server id: send the pattern and colour.
        await sendTouch(pattern: meaning.pattern, generation: meaning.touchGeneration,
                        colorRGB: meaning.colorRGB, endColorRGB: meaning.endColorRGB, toBondID: toBondID)
    }

    // MARK: - Profile

    /// Pushes the user's profile (name, colour, photo) to every partner: the original backend
    /// and each iCloud bond.
    func publishProfile() async {
        let p = store.profile
        guard p.isComplete else { return }
        legacyPublishProfile(name: p.name, colorRGB: p.colorRGB)
        for partner in cloudPartners {
            try? await relay.sendProfile(name: p.name, colorRGB: p.colorRGB, photo: myPhotoFileURL,
                                         pushToken: myPushToken, bond: partner.bond, senderID: myUserID)
        }
    }

    /// iOS handed us a fresh APNs device token — remember it and push it out to partners so
    /// they can wake this phone directly when they touch.
    func updatePushToken(_ hex: String) {
        guard hex != myPushToken else { return }
        myPushToken = hex
        Task { await publishProfile() }
    }

    /// Wakes a cloud partner's phone directly via APNs (no-op if their token or our key is
    /// missing — CloudKit's own push still covers that case).
    private func pushPartner(bondID: String, title: String, body: String) async {
        guard let token = partnerPushTokens[bondID], !token.isEmpty else { return }
        // Their bracelet is connected → it plays the touch; don't buzz their phone too.
        let silent = partnerBraceletConnected[bondID] == true
        await APNsClient.shared.send(toDeviceToken: token, title: title, body: body, silent: silent,
                                     collapseID: "touch-\(bondID)")
    }

    /// Unbonds: deletes the iCloud bond (owner only) or cancels the original-app bond, and
    /// drops the partner locally.
    func removeBond(_ bond: Bond) async {
        if bond.legacy { await legacyCancelBond(bond); return }
        do {
            try await relay.deleteBond(bond)
            cloudPartners.removeAll { $0.id == bond.id }
            cloudPending.removeAll { $0.id == bond.id }
            store.cloudBondCodes[bond.id] = nil
            if selectedPartnerID == bond.id { selectedPartnerID = partners.first?.id }
        } catch {
            statusLine = "Couldn't remove: \(error.localizedDescription)"
        }
    }

    // MARK: - Receiving

    func handleRemoteNotification() async { await refreshAll() }

    func refreshAll() async {
        defer { autoLinkPartners() }
        // An invite we created: once the partner's profile appears, they've joined — make
        // them a partner (no relaunch needed).
        for bond in cloudPending {
            guard let name = await relay.joinedPartnerName(bond) else { continue }
            var joined = bond
            joined.pending = false
            joined.partnerName = name
            cloudPending.removeAll { $0.id == bond.id }
            if !cloudPartners.contains(where: { $0.id == joined.id }) { cloudPartners.append(Partner(bond: joined)) }
            if selectedPartnerID == nil { selectedPartnerID = joined.id }
            if pendingInviteURL.flatMap(CloudRelay.code(fromURL:)) == joined.id { pendingInviteURL = nil }
            NetLog.shared.log(.ok, "\(name) joined your invite (iCloud)")
        }
        // Make sure every cloud partner — including one who just accepted an invite — has
        // this device's current profile (name, colour, photo, push token) once per launch.
        let unsent = cloudPartners.filter { !profileSyncedBondIDs.contains($0.id) }
        if !unsent.isEmpty {
            let p = store.profile
            for partner in unsent {
                do {
                    try await relay.sendProfile(name: p.name.isEmpty ? "Me" : p.name, colorRGB: p.colorRGB,
                                                photo: myPhotoFileURL, pushToken: myPushToken,
                                                bond: partner.bond, senderID: myUserID)
                    profileSyncedBondIDs.insert(partner.id)   // only once it actually landed
                } catch {
                    NetLog.shared.log(.fail, "iCloud: profile not sent", error.localizedDescription)
                }
            }
        }
        for index in cloudPartners.indices {
            let partner = cloudPartners[index]
            guard let events = try? await relay.fetchNewEvents(bond: partner.bond, myUserID: myUserID) else { continue }
            guard index < cloudPartners.count, cloudPartners[index].id == partner.id else { continue }
            recordTouches(events.touches.map { var t = $0; t.bondID = partner.id; return t })
            if !events.touches.isEmpty {
                NetLog.shared.log(.recv, "Received \(events.touches.count) touch(es) ← \(partner.displayName) (iCloud)")
            }
            if !events.messages.isEmpty {
                appendChat(events.messages, bondID: partner.id)
            }
            if let name = events.partnerName { cloudPartners[index].displayName = name }
            if let color = events.partnerColorRGB { cloudPartners[index].colorRGB = color }
            if let photo = events.partnerPhoto { setPartnerPhoto(photo, bondID: partner.id) }
            if let token = events.partnerPushToken, !token.isEmpty { partnerPushTokens[partner.id] = token }
            if let p = events.presence {
                cloudPartners[index].presence = p
                cloudPartners[index].online = p.online
                cloudPartners[index].lastSeen = p.sentAt
                // Cleared when they stop sharing location.
                cloudPartners[index].latitude = p.lat
                cloudPartners[index].longitude = p.lng
                if let ready = p.bracelet { partnerBraceletConnected[partner.id] = ready }
            }

            // Only the selected partner's touches/heartbeat drive the bracelet.
            if partner.id == selectedPartnerID, !store.doNotDisturb {
                // Only fresh touches buzz the band — not history fetched after a reinstall.
                for touch in events.touches where Date().timeIntervalSince(touch.sentAt) < 120 {
                    feel(touch)
                }
                // A heartbeat plays once, for 5 s — and only if it's fresh (not one that was
                // sent long ago and is only now being fetched).
                if let bpm = events.latestBPM, let at = events.latestBPMAt,
                   Date().timeIntervalSince(at) < 60 {
                    feelHeartbeat(bpm: bpm)
                }
            }
        }
    }

    // MARK: - Heartbeat (a button press sends 5 s of your heartbeat)

    /// Sends the user's current heartbeat to the selected partner, once: their bracelet
    /// beats at that rate for 5 seconds. iCloud partners get a heartbeat record; a partner
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
        defer { Task { @MainActor in try? await Task.sleep(nanoseconds: 5_000_000_000); self.sendingHeartbeat = false } }
        if bond.legacy {
            // 5 s of heartbeats as an on/off pattern, shaped like a real heart: each beat is
            // a big "lub" press (150 ms), a short gap, a smaller "dub" press (90 ms), then a
            // rest to the next beat. On the partner's bracelet it buzzes lub-dub, lub-dub.
            let period = 60_000 / max(bpm, 30)
            let beats = max(1, 5_000 / period)
            var pattern: [Int] = []
            let lubDub = period >= 150 + 150 + 90 + 80
            for i in 0..<beats {
                pattern.append(150)                                   // lub (on)
                if lubDub {
                    pattern.append(150)                               // gap (off)
                    pattern.append(90)                                // dub (on)
                    if i < beats - 1 { pattern.append(max(period - 390, 80)) }  // rest (off)
                } else if i < beats - 1 {
                    pattern.append(max(period - 150, 80))             // rest (off)
                }
            }
            await sendTouch(pattern: pattern, generation: 2, colorRGB: 0xE85D75, toBondID: bond.id)
        } else {
            do {
                try await relay.sendHeartbeat(bpm: bpm, bond: bond, senderID: myUserID)
                let me = store.profile.name.isEmpty ? "Someone" : store.profile.name
                await pushPartner(bondID: bond.id, title: "\(me)'s heartbeat", body: "💓 \(bpm) bpm")
            }
            catch { statusLine = "Heartbeat failed: \(error.localizedDescription)"; return nil }
        }
        return bpm
    }
}
