import CloudKit
import Combine
import CoreLocation
import Foundation
import UserNotifications
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
    private var missedPending: Set<UUID> = []
    /// Per iCloud bond: how far the partner's phone has received our chat messages.
    @Published var partnerSeenMessage: [String: Int] = [:]

    /// Adds touches to the feed, skipping ones already present (the backends re-fetch on
    /// each launch), sorting by time, and saving to disk so the feed survives app updates.
    func recordTouches(_ touches: [TouchMessage]) {
        var added = false
        for var t in touches where !historyIDs.contains(t.id) {
            if missedPending.remove(t.id) != nil { t.missed = true }
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
        if let bpm = touch.heartbeatBPM { feelHeartbeat(touch, bpm: bpm); return }
        let foreground = UIApplication.shared.applicationState == .active
        if bracelet.play(touch, holdIfOffline: !foreground) { return }
        if foreground {
            haptics.play(touch)
            NetLog.shared.log(.recv, "Bracelet not connected — played the touch on the phone")
        }
    }

    /// A heartbeat on screen now (the live EKG card), and its monitor beep.
    @Published var heartbeatShow: HeartbeatShow?
    /// Counts double taps on the user's bracelet (Private Space unlocks on one).
    @Published var braceletDoubleTaps = 0
    private let heartbeatSound = HeartbeatSound()

    /// Plays a heartbeat: on a Bond Touch More the EKG itself (the light rests mid-band and
    /// jumps up and down on each beat, the motors following); on other bracelets a pulse per
    /// beat; with no bracelet, on the phone. On screen it's a live EKG with a beep per beat.
    func feelHeartbeat(_ touch: TouchMessage, bpm: Int) {
        let foreground = UIApplication.shared.applicationState == .active
        let seconds = 5.0
        if bracelet.isReady {
            if bracelet.isThirdGeneration { _ = bracelet.play(touch, holdIfOffline: false) }
            else { bracelet.playHeartbeat(bpm: bpm, seconds: seconds, colorRGB: touch.colorRGB) }
        } else if foreground {
            haptics.playHeartbeat(bpm: bpm, seconds: seconds)
        }
        guard foreground else { return }
        let mine = touch.senderID == myUserID || touch.senderID == ChatMessage.legacySelf
        let name = mine ? "Your" : (partners.first { $0.id == touch.bondID }?.displayName ?? "Partner")
        let show = HeartbeatShow(bpm: bpm, colorRGB: touch.colorRGB, name: mine ? "Your" : name,
                                 start: Date(), seconds: seconds)
        heartbeatShow = show
        heartbeatSound.play(bpm: bpm, seconds: seconds, start: show.start)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((seconds + 0.6) * 1_000_000_000))
            if self.heartbeatShow?.id == show.id { self.heartbeatShow = nil }
        }
    }

    func dismissHeartbeat() {
        heartbeatShow = nil
        heartbeatSound.stop()
    }

    /// A heartbeat as a touch: the EKG on the Bond Touch More bar, tagged with its BPM.
    func heartbeatTouch(bpm: Int, bondID: String, senderID: String, id: UUID = UUID(), sentAt: Date = Date()) -> TouchMessage {
        TouchMessage(id: id, bondID: bondID, senderID: senderID, pattern: EKG.samples(bpm: bpm),
                     generation: 3, colorRGB: EKG.colorRGB, sentAt: sentAt, heartbeatBPM: bpm)
    }
    let store = LocalStore()
    let heart = HeartRateService()
    let location = LocationService()
    let relay = CloudRelay()

    /// Location sharing — on unless the user turned it off. Kept in the Keychain, so it stays
    /// as set across updates and reinstalls.
    @Published var sharingLocation = StickySetting.bool("shareLocation", default: true)

    var selectedPartner: Partner? { partners.first { $0.id == selectedPartnerID } }
    var activeBond: Bond? { selectedPartner?.bond }

    init() {
        messagesByBond = ChatArchive.load()
        // A send cut short by the app closing didn't finish.
        history = TouchArchive.load().map { var t = $0; if t.delivery == .sending { t.delivery = .failed }; return t }
        historyIDs = Set(history.map { $0.id })
        bracelet.$state.receive(on: DispatchQueue.main).assign(to: &$braceletState)
        bracelet.$heartbeatActive.receive(on: DispatchQueue.main).assign(to: &$partnerHeartbeatActive)
        location.onUpdate = { [weak self] fix in Task { @MainActor in await self?.broadcastLocation(fix) } }
        location.onArrive = { [weak self] id in Task { @MainActor in await self?.arrived(at: id) } }
        store.$savedPlaces
            .sink { [weak self] places in Task { @MainActor in self?.location.monitor(places) } }
            .store(in: &statusWatch)
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
            Task { @MainActor in
                if let bpm = touch.heartbeatBPM { self?.haptics.playHeartbeat(bpm: bpm) } else { self?.haptics.play(touch) }
            }
        }
        // A double tap on the bracelet is an action, not a touch: it unlocks Private Space.
        bracelet.onDoubleTap = { [weak self] in
            Task { @MainActor in
                self?.braceletDoubleTaps += 1
                NetLog.shared.log(.recv, "Bracelet double-tapped")
            }
        }
        // Choosing a partner on the bracelet selects them in the app (slot n = n-th partner,
        // as the partner menu is laid out), and choosing in the app tells the bracelet.
        bracelet.onSlotSelected = { [weak self] slot in
            Task { @MainActor in
                guard let self, self.partners.indices.contains(slot - 1) else { return }
                self.selectedPartnerID = self.partners[slot - 1].id
            }
        }
        $selectedPartnerID.removeDuplicates()
            .sink { [weak self] id in
                Task { @MainActor in
                    guard let self, let id, let i = self.partners.firstIndex(where: { $0.id == id }) else { return }
                    self.bracelet.selectPartnerSlot(i + 1)
                }
            }
            .store(in: &statusWatch)
        // Low bracelet battery: one phone notification per discharge, as the original.
        bracelet.$batteryPercent.combineLatest(bracelet.$charging)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pct, charging in
                Task { @MainActor in self?.checkBraceletBattery(pct, charging: charging == true) }
            }
            .store(in: &statusWatch)
        // The bracelet shows the user's own colour (sent at every pairing).
        bracelet.setUserColor(store.profile.colorRGB)
        watch.start(self)
        recovery.start(bracelet)
        AppModel.shared = self
    }

    private var batteryAlerted = UserDefaults.standard.bool(forKey: "BondBatteryAlerted") {
        didSet { UserDefaults.standard.set(batteryAlerted, forKey: "BondBatteryAlerted") }
    }

    /// Notifies once when the bracelet runs low (its own low-battery level when it reports
    /// one, else 15 %); re-armed once it's charging or back above 30 %.
    private func checkBraceletBattery(_ pct: Int?, charging: Bool) {
        guard let pct else { return }
        if charging || pct >= 30 { batteryAlerted = false; return }
        let low = bracelet.batteryAlert?.lowPercent ?? 15
        guard pct <= low, !batteryAlerted else { return }
        batteryAlerted = true
        let content = UNMutableNotificationContent()
        content.title = "Bracelet battery low"
        content.body = "Your bracelet is at \(pct)%. Charge it soon so you don't miss any touches."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "bracelet-battery", content: content, trigger: nil))
        NetLog.shared.log(.fail, "Bracelet battery low", "\(pct)%")
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
        StickySetting.set("shareLocation", on)
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

    // MARK: - Saved places

    /// Arrived at a saved place: every partner feels a touch saying so (once per place per
    /// 30 minutes, so hovering at the edge doesn't repeat it).
    private func arrived(at placeID: String) async {
        guard let place = store.savedPlaces.first(where: { $0.id.uuidString == placeID }), place.notifyPartners else { return }
        let key = "arrived-\(placeID)"
        if let last = UserDefaults.standard.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 30 * 60 { return }
        UserDefaults.standard.set(Date(), forKey: key)
        if !ready { await bootstrap() }
        NetLog.shared.log(.send, "Arrived at \(place.name) — telling partners")
        let arrival = TouchMeaning(label: "Arrived at \(place.name)", emoji: "📍", colorRGB: store.profile.colorRGB,
                                   pattern: [120, 120, 120])     // two short taps
        for partner in partners {
            await sendTouch(pattern: arrival.pattern, generation: 2, colorRGB: arrival.colorRGB,
                            toBondID: partner.id, meaning: arrival)
        }
    }

    // MARK: - Lifecycle

    private var bootstrapTask: Task<Void, Never>?

    /// Starts everything up. Safe to call from several places (the app delegate at launch —
    /// also a background launch — and the first screen): it runs once, later callers wait
    /// for it. It can run again only if iCloud wasn't ready (e.g. not signed in yet).
    func bootstrap() async {
        if let running = bootstrapTask { await running.value; return }
        let task = Task { await self.runBootstrap() }
        bootstrapTask = task
        await task.value
        if !ready { bootstrapTask = nil }
    }

    private var inForeground: Bool { UIApplication.shared.applicationState != .background }

    private func runBootstrap() async {
        loadMyPhoto()
        bracelet.startScanning()
        // The original backend works without iCloud, so start it first and independently.
        startLegacySync()
        // Sharing stays as the user left it (on by default) — it isn't reset by an update.
        if sharingLocation { setLocationSharing(true) }
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
            migrateMeaningLibraries()
            if selectedPartnerID == nil { selectedPartnerID = partners.first?.id }
            ready = true
            statusLine = "Ready."
            await publishProfile()
            await setOnline(inForeground)
            await refreshAll()
            await resendRecentFailures()
            if inForeground { startCloudPolling() }   // a background launch just handles its push
            if UIApplication.shared.backgroundRefreshStatus != .available {
                NetLog.shared.log(.fail, "Background App Refresh is off for this app",
                                  "Turn it on in Settings → General → Background App Refresh, or touches can't wake the bracelet while the app is closed")
            }
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
            // Private Space messages and photos are kept 72 hours.
            var chats = messagesByBond
            if ChatArchive.expire(&chats) { messagesByBond = chats; ChatArchive.save(chats) }
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
    ///
    /// Unless `meaning` is given (or `matchMeaning` is false), the touch is first checked
    /// against the partner's saved meanings: a close match is sent *as* that meaning — its
    /// colours and name, and for an original-app partner by meaning id, so their bracelet
    /// plays it as the meaning.
    func sendTouch(pattern: [Int], generation: Int = 2, colorRGB: Int, endColorRGB: Int? = nil,
                   toBondID: String? = nil, meaning given: TouchMeaning? = nil, matchMeaning: Bool = true,
                   heartbeatBPM: Int? = nil) async {
        guard let bond = bond(for: toBondID) else { return }
        // Finish sending even if the app goes to the background meanwhile (e.g. a touch
        // made on the bracelet while the phone is locked).
        let bg = UIApplication.shared.beginBackgroundTask(withName: "send-touch")
        defer { UIApplication.shared.endBackgroundTask(bg) }

        let meaning = given ?? (matchMeaning ? matchingMeaning(pattern: pattern, generation: generation,
                                                               in: meanings(for: bond)) : nil)
        if let meaning, given == nil {
            NetLog.shared.log(.ok, "Touch matches \"\(meaning.label)\" — sending it as that meaning")
        }
        // A meaning goes out as itself: its own pattern and colours.
        var touch = TouchMessage(bondID: bond.id, senderID: myUserID,
                                 pattern: meaning?.pattern ?? pattern,
                                 generation: meaning?.touchGeneration ?? generation,
                                 colorRGB: meaning?.colorRGB ?? colorRGB,
                                 endColorRGB: meaning?.endColorRGB ?? endColorRGB,
                                 meaningLabel: meaning?.label, meaningEmoji: meaning?.emoji,
                                 heartbeatBPM: heartbeatBPM)
        touch.delivery = .sending
        recordTouch(touch)          // listed straight away as "Sending…"
        await transmit(touch, bond: bond, meaning: meaning)
    }

    /// Sends a touch already in history and updates its delivery status (Sent, or Failed).
    private func transmit(_ touch: TouchMessage, bond: Bond, meaning: TouchMeaning?) async {
        let route = bond.legacy ? "original Bond API" : "iCloud"
        NetLog.shared.log(.send, "Send \(meaning.map { "\"\($0.label)\"" } ?? "touch") → \(bond.partnerName) (\(route))",
                          "gen \(touch.generation), \(touch.pattern.count) samples")
        do {
            if bond.legacy, let serverID = meaning?.serverID {
                // The original app sends a saved meaning by id; the partner's bracelet then
                // lights and buzzes it as that meaning.
                try await BondBackend.sendMeaningTouch(bondId: bond.id, meaningId: serverID,
                                                       bearer: try await legacyToken())
                updateHistory(touch.id) { $0.delivery = .sent }
            } else if bond.legacy {
                // As the original: the server tells us which saved meaning it matched.
                let matched = try await legacySendTouch(touch, bond: bond)
                updateHistory(touch.id) { t in
                    t.delivery = .sent
                    if let matched, t.meaningLabel == nil { t.meaningLabel = matched.label; t.meaningEmoji = matched.emoji }
                }
            } else {
                let seq = try await relay.sendTouch(touch, bond: bond)
                updateHistory(touch.id) { $0.delivery = .sent; $0.ringSeq = seq }
                NetLog.shared.log(.ok, "Touch → iCloud accepted", "\(bond.partnerName)")
                // Wake their phone right away (CloudKit's own push can lag in deep sleep).
                let me = store.profile.name.isEmpty ? "Someone" : store.profile.name
                if let bpm = touch.heartbeatBPM {
                    await pushPartner(bondID: bond.id, title: "\(me)'s heartbeat", body: "💓 \(bpm) BPM", touch: touch)
                } else if touch.meaningEmoji == "📍", let label = touch.meaningLabel {
                    await pushPartner(bondID: bond.id, title: "\(me) arrived", body: "📍 \(label)", touch: touch)
                } else {
                    let body = touch.meaningLabel.map { "\(touch.meaningEmoji ?? "") \($0)".trimmingCharacters(in: .whitespaces) } ?? "❤️"
                    await pushPartner(bondID: bond.id, title: "\(me) touched you", body: body, touch: touch)
                }
            }
        } catch {
            updateHistory(touch.id) { $0.delivery = .failed }
            statusLine = "Send failed: \(error.localizedDescription)"
            NetLog.shared.log(.fail, "Send touch failed (\(route))", error.localizedDescription)
        }
    }

    /// Changes one history entry and saves.
    func updateHistory(_ id: UUID, _ change: (inout TouchMessage) -> Void) {
        guard let i = history.firstIndex(where: { $0.id == id }) else { return }
        change(&history[i])
        TouchArchive.save(history)
    }

    /// Sends a failed touch again (same touch, so it isn't listed twice).
    func resend(_ touch: TouchMessage) async {
        guard touch.delivery == .failed, let bond = bond(for: touch.bondID) else { return }
        let bg = UIApplication.shared.beginBackgroundTask(withName: "resend-touch")
        defer { UIApplication.shared.endBackgroundTask(bg) }
        updateHistory(touch.id) { $0.delivery = .sending }
        let meaning = touch.meaningLabel.flatMap { label in meanings(for: bond).first { $0.label == label } }
        await transmit(touch, bond: bond, meaning: meaning)
    }

    /// As the original: touches that failed in the last 15 minutes are sent again when the
    /// app starts (older ones stay Failed — tap to retry).
    func resendRecentFailures() async {
        let recent = history.filter { $0.delivery == .failed && Date().timeIntervalSince($0.sentAt) < 15 * 60 }
        for t in recent { await resend(t) }
    }

    /// A touch that arrived but didn't play. It may not be in history yet (the original
    /// backend's sync delivers first), so it's flagged when it's added.
    private func markMissed(_ id: UUID) {
        if historyIDs.contains(id) { updateHistory(id) { $0.missed = true } } else { missedPending.insert(id) }
    }

    /// Marks our touches the partner's phone has received as Seen.
    private func markSeen(bondID: String, upTo seen: Int) {
        var changed = false
        for i in history.indices where history[i].bondID == bondID && history[i].delivery == .sent {
            if let seq = history[i].ringSeq, seq <= seen { history[i].delivery = .seen; changed = true }
        }
        if changed { TouchArchive.save(history) }
    }

    /// Sends a saved meaning (Touch Language) — by id to an original-app partner, as a
    /// labelled touch over iCloud.
    func sendMeaning(_ meaning: TouchMeaning, toBondID: String? = nil) async {
        await sendTouch(pattern: meaning.pattern, generation: meaning.touchGeneration,
                        colorRGB: meaning.colorRGB, endColorRGB: meaning.endColorRGB,
                        toBondID: toBondID, meaning: meaning)
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
                                         pushToken: myPushToken, meanings: sharedLibrary(partner.id),
                                         bond: partner.bond, senderID: myUserID)
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
    ///
    /// A touch rides inside the push, sealed with the bond's key, so the partner's phone can
    /// play it on their bracelet the moment it wakes — no iCloud fetch first (a background
    /// wake only gets a few seconds). The bond is named by its opaque locator, never its code.
    private func pushPartner(bondID: String, title: String, body: String, touch: TouchMessage? = nil) async {
        guard let token = partnerPushTokens[bondID], !token.isEmpty else { return }
        // Their bracelet is connected → it plays the touch; don't buzz their phone too.
        let silent = partnerBraceletConnected[bondID] == true
        let locator = BondCrypto.locator(forCode: bondID)
        var extra: [String: Any] = ["bl": locator]
        if let touch, let sealed = BondCrypto.seal(touch, code: bondID) { extra["bt"] = sealed.base64EncodedString() }
        await APNsClient.shared.send(toDeviceToken: token, title: title, body: body, silent: silent,
                                     collapseID: "t-\(locator.prefix(16))", extra: extra)
    }

    /// The touch carried in a partner's push, decrypted with that bond's key.
    private func touchFromPush(_ userInfo: [AnyHashable: Any]) -> TouchMessage? {
        guard let locator = userInfo["bl"] as? String, let b64 = userInfo["bt"] as? String,
              let data = Data(base64Encoded: b64),
              let partner = cloudPartners.first(where: { BondCrypto.locator(forCode: $0.id) == locator }),
              let sent = BondCrypto.open(TouchMessage.self, from: data, code: partner.id) else { return nil }
        // Same id and sender form as when it's fetched from iCloud, so it's never doubled.
        let partnerRole = partner.bond.isOwner ? "B" : "A"
        return TouchMessage(id: sent.id, bondID: partner.id, senderID: "\(partner.id)-\(partnerRole)",
                            pattern: sent.pattern, generation: sent.generation, colorRGB: sent.colorRGB,
                            endColorRGB: sent.endColorRGB, sentAt: sent.sentAt,
                            meaningLabel: sent.meaningLabel, meaningEmoji: sent.meaningEmoji,
                            heartbeatBPM: sent.heartbeatBPM)
    }

    /// Plays a partner's incoming touch on the bracelet (or the phone) once — however many
    /// ways it arrives (push, iCloud fetch, original backend) — from any partner, in their
    /// slot, up to 15 minutes old (as the original app), and not during Do Not Disturb.
    private var deliveredTouchIDs: Set<UUID> = []
    func deliver(_ touch: TouchMessage) {
        // A heartbeat is live: it plays only within 2 minutes (it's still kept in history).
        let maxAge: TimeInterval = touch.heartbeatBPM == nil ? 15 * 60 : 120
        guard deliveredTouchIDs.insert(touch.id).inserted else { return }
        // Not played — too old, or Do Not Disturb: flagged Missed in history, as the original.
        if Date().timeIntervalSince(touch.sentAt) >= maxAge || store.quiet() {
            if store.quiet() {
                NetLog.shared.log(.recv, "Do Not Disturb — touch not played", partners.first { $0.id == touch.bondID }?.displayName ?? "")
            }
            markMissed(touch.id)
            return
        }
        feel(touch)
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

    /// A partner's push — possibly with the app just launched in the background. Finishes
    /// starting up if needed, plays the touch the push carries straight away, syncs the rest,
    /// then waits until the bracelet has the whole touch before letting iOS suspend the app.
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any] = [:]) async {
        if !ready { await bootstrap() }
        if let touch = touchFromPush(userInfo) {
            NetLog.shared.log(.recv, "Touch in push ← \(partners.first { $0.id == touch.bondID }?.displayName ?? "partner")")
            recordTouches([touch])
            deliver(touch)
        }
        await refreshAll()
        await bracelet.waitUntilIdle(timeout: 8)
    }

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
                                                meanings: sharedLibrary(partner.id),
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
            if let seen = events.partnerSeenTouch { markSeen(bondID: partner.id, upTo: seen) }
            if let seen = events.partnerSeenMessage { partnerSeenMessage[partner.id] = seen }
            if let shared = events.partnerMeanings { mergeMeanings(shared, bondID: partner.id) }
            if let p = events.presence {
                cloudPartners[index].presence = p
                cloudPartners[index].online = p.online
                cloudPartners[index].lastSeen = p.sentAt
                // Cleared when they stop sharing location.
                cloudPartners[index].latitude = p.lat
                cloudPartners[index].longitude = p.lng
                if let ready = p.bracelet { partnerBraceletConnected[partner.id] = ready }
            }

            // Every partner's touches play, each in its own slot (as the original app); `deliver`
            // skips stale ones, repeats (already played from a push) and Do Not Disturb.
            events.touches.forEach(deliver)
            // A heartbeat from an older build (its own record, not in the touch ring): listed
            // in history like any heartbeat, and played if fresh.
            if let bpm = events.latestBPM, let at = events.latestBPMAt {
                let hb = heartbeatTouch(bpm: bpm, bondID: partner.id, senderID: "\(partner.id)-\(partner.bond.isOwner ? "B" : "A")",
                                        id: TouchMessage.stableID(from: "hb-\(partner.id)-\(Int(at.timeIntervalSince1970))"),
                                        sentAt: at)
                recordTouch(hb)
                deliver(hb)
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
        statusLine = ""
        defer { Task { @MainActor in try? await Task.sleep(nanoseconds: 5_000_000_000); self.sendingHeartbeat = false } }
        // It goes as a touch tagged with the BPM: over iCloud the EKG itself (in the touch ring
        // and inside the push, so it plays right away and shows in history on both phones);
        // to an original-app partner, a press per beat (their app only knows touches).
        if bond.legacy {
            await sendTouch(pattern: EKG.onOff(bpm: bpm), generation: 2, colorRGB: EKG.colorRGB,
                            toBondID: bond.id, matchMeaning: false, heartbeatBPM: bpm)
        } else {
            await sendTouch(pattern: EKG.samples(bpm: bpm), generation: 3, colorRGB: EKG.colorRGB,
                            toBondID: bond.id, matchMeaning: false, heartbeatBPM: bpm)
        }
        if statusLine.hasPrefix("Send failed") { statusLine = "Heartbeat " + statusLine.lowercased(); return nil }
        return bpm
    }
}
