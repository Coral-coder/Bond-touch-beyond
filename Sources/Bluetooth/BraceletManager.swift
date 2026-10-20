import CoreBluetooth
import Foundation
import UIKit

enum BraceletState: Equatable {
    case bluetoothOff
    case scanning
    case connecting
    case connected
    case disconnected
}

/// CoreBluetooth central for a Bond Touch bracelet. Scans by advertised name, connects,
/// detects the bracelet generation (v1/v2/v3/v4/mini), runs the token/AUID pairing
/// handshake, subscribes to the state + event channels, and sends touches and buzz/glow
/// using the per-generation wire format in `BondGATT`. Writes are serialised.
final class BraceletManager: NSObject, ObservableObject {
    @Published private(set) var state: BraceletState = .disconnected
    /// Battery percentage (last known value): the standard battery service (2A19), or d3c0ff06
    /// on v1 (from millivolts) and v2/v4/mini (byte 0).
    @Published private(set) var batteryPercent: Int?
    /// When the bracelet was last connected (now, while it is), kept across launches.
    @Published private(set) var lastConnectedAt: Date? =
        UserDefaults.standard.object(forKey: "BondBraceletLastConnected") as? Date {
        didSet { UserDefaults.standard.set(lastConnectedAt, forKey: "BondBraceletLastConnected") }
    }
    /// Delivered when the user makes a touch on their own bracelet: the pattern, its
    /// generation (3 = Bond Touch More position samples, 2 = on/off milliseconds), and — on a
    /// Bond Touch More — the bond of the partner slot it was made for (nil = selected partner).
    var onLocalTap: (([Int], Int, String?) -> Void)?
    /// A double tap on the bracelet — an action, not a touch (v2/v4/mini event 0x17, Bond
    /// Touch More event 178; the original v1 app raises it on paired state 247).
    var onDoubleTap: (() -> Void)?
    /// The partner slot (1…3) the user picked on the bracelet itself (Bond Touch More event
    /// 180; Bond Touch 4 when a touch is recorded for another slot).
    var onSlotSelected: ((Int) -> Void)?

    /// Device info: firmware (Bond Touch More from its 0xAC answer, v1 from d3c0ff03, others
    /// from 2A26), model number (2A24), charging (v1/v2/v4/mini state channel; "full" counts
    /// as charging, as in the original), and a Bond Touch More's battery-alert settings.
    @Published private(set) var firmwareVersion: String?
    @Published private(set) var modelNumber: String?
    @Published private(set) var charging: Bool?
    @Published private(set) var batteryAlert: BondGATT.BatteryAlertSettings?
    /// The bracelet is in setup mode and waits for a double tap to pair with this phone
    /// (the original shows "double-tap the flashing bracelet").
    @Published private(set) var needsSetupTap = false

    /// A newer official firmware than the bracelet's, built into the app. Checked each time
    /// the firmware is read, as the original's FirmwareHelper (older than the latest for its
    /// generation → update). The original then refuses to use the bracelet until it's
    /// updated; we only offer it.
    struct FirmwareUpdate: Equatable {
        let model: BraceletModel
        let current: String
        let latest: String
        let file: URL
    }
    @Published private(set) var updateAvailable: FirmwareUpdate?

    /// The original refuses an update at 40 % battery or less (DfuInfoViewModel); here it's
    /// also allowed on the charger. An unknown level doesn't block, as in the original.
    var batteryAllowsUpdate: Bool {
        charging == true || (batteryPercent.map { $0 > 40 } ?? true)
    }

    /// Set once the bracelet was told to restart in update mode: it's not reconnected as a
    /// bracelet until the updater is done with it (`resumeAfterRecovery`/`endUpdateHandoff`).
    private var dfuHandoff = false

    /// Restarts the bracelet in its update (DFU) bootloader, as the original's startDfuMode
    /// (C()): v1 DfuCommand 0x25, v2/v4/mini `[0x25,0,0x11,0x22,0x33,0x44]`, Bond Touch More
    /// `[1,0x30]` + `[1,0x2A]`. It then advertises BOND_…_DFU and `dfuDevice` hands it to the
    /// updater. False if the bracelet isn't connected.
    @discardableResult
    func enterUpdateMode() -> Bool {
        guard isReady, let gen else { return false }
        dfuHandoff = true
        dfuDevice = nil
        switch gen {
        case .v1: enqueue([v1.enterUpdateMode()])
        case .v2, .v4, .mini: enqueue([BondGATT.v2EnterUpdateMode])
        case .v3: enqueue(BondGATT.v3EnterUpdateMode)
        }
        NetLog.shared.record(.send, "Bracelet: restarting in update mode", firmwareVersion.map { "firmware \($0)" } ?? "")
        return true
    }

    /// The bracelet never showed up in update mode: use it as a bracelet again.
    func endUpdateHandoff() {
        guard dfuHandoff else { return }
        dfuHandoff = false
        if !linkUp { startScanning() }
    }

    /// FirmwareHelper.a: an update is offered when the firmware is known and older than the
    /// latest for the generation, and the app has that firmware built in.
    private func checkFirmware() {
        guard let gen, let fw = firmwareVersion else { updateAvailable = nil; return }
        let latest = gen.latestFirmware
        let current = BondFirmwareVersion(fw)
        guard !current.isUnknown, current < latest.version,
              let file = Bundle.main.url(forResource: latest.file, withExtension: "zip") else {
            updateAvailable = nil
            return
        }
        updateAvailable = FirmwareUpdate(model: latest.model, current: fw,
                                         latest: latest.version.description, file: file)
        NetLog.shared.record(.send, "Bracelet firmware update available", "\(fw) → \(latest.version)")
    }

    // The user's bracelet settings, kept across launches and (re)applied after every pairing
    // (the original's UserBraceletData + SAVED_USER_INDEX).
    private let defaults = UserDefaults.standard
    private var vibrationLevel: Int? {
        get { (defaults.object(forKey: "BondVibrationLevel") as? Int).flatMap { BondGATT.vibrationLevels.contains($0) ? $0 : nil } }
        set { defaults.set(newValue, forKey: "BondVibrationLevel") }
    }
    private var vibrationBalance: Int {
        get { (defaults.object(forKey: "BondVibrationBalance") as? Int) ?? 2 }
        set { defaults.set(newValue, forKey: "BondVibrationBalance") }
    }
    private var userColor: Int? {
        get { defaults.object(forKey: "BondUserColor") as? Int }
        set { defaults.set(newValue, forKey: "BondUserColor") }
    }
    private var selectedSlot: Int {
        get { (defaults.object(forKey: "BondSelectedSlot") as? Int).flatMap { (1...3).contains($0) ? $0 : nil } ?? 1 }
        set { defaults.set(newValue, forKey: "BondSelectedSlot") }
    }

    /// Vibration strength (28, 33, 40, 58, 60, 73, 80, 88 or 100) and left/right balance
    /// (0…4, 2 = centre). Bond Touch More: `[1,0x48,2,level,balance,3]`; v2/v4/mini: the
    /// motor-strength setting (no balance); classic v1 has no setting.
    func setVibration(level: Int, balance: Int) {
        guard BondGATT.vibrationLevels.contains(level), (0...4).contains(balance) else { return }
        vibrationLevel = level
        vibrationBalance = balance
        guard paired, let gen else { return }
        enqueue(vibrationWrites(gen, level: level, balance: balance))
    }

    /// Plays a vibration once without saving it (Bond Touch More `[1,0x48,0,…]`, v2/v4/mini
    /// a 2 s motor-only frame).
    func previewVibration(level: Int, balance: Int) {
        guard isReady, let gen, BondGATT.vibrationLevels.contains(level), (0...4).contains(balance) else { return }
        switch gen {
        case .v3: enqueue([BondGATT.v3VibrationPreview(level: UInt8(level), balance: UInt8(balance))])
        case .v2, .v4, .mini: enqueue([BondGATT.v2VibrationPreview(level: level)])
        case .v1: break
        }
    }

    /// The user's own colour: v2 touch + double-tap colour, v4/mini touch colour + own menu
    /// entry, v1 its colour config. (The original sends nothing to a Bond Touch More.)
    func setUserColor(_ rgb: Int) {
        userColor = rgb & 0xFFFFFF
        guard paired, let gen else { return }
        enqueue(userColorWrites(gen, rgb: rgb & 0xFFFFFF))
    }

    /// Lights the bracelet in a colour until `endColorPreview()`.
    func previewColor(_ rgb: Int) {
        guard isReady, let gen else { return }
        switch gen {
        case .v3: enqueue([BondGATT.v3Color(rgb & 0xFFFFFF)])
        case .v2, .v4, .mini: enqueue([BondGATT.v2HoldColor(rgb)])
        case .v1: enqueue([v1.previewColor(rgb)])
        }
    }

    func endColorPreview() {
        guard isReady, let gen else { return }
        switch gen {
        case .v3: enqueue([BondGATT.v3LedsOff])
        case .v2, .v4, .mini: enqueue([BondGATT.v2LedsOff])
        case .v1: enqueue([v1.colorOff()])
        }
    }

    /// Picks the partner slot (1…3) the bracelet sends to. Only the Bond Touch 4 takes it
    /// from the app (SELECTED_USER); it's remembered and re-sent after pairing.
    func selectPartnerSlot(_ slot: Int) {
        guard (1...3).contains(slot) else { return }
        selectedSlot = slot
        guard gen == .v4, paired else { return }
        v4Selected = slot
        enqueue(v4SelectWrites(slot))
    }

    private func reportSlotSelected(_ slot: Int) {
        selectedSlot = slot
        onSlotSelected?(slot)
    }

    private func vibrationWrites(_ gen: BondGeneration, level: Int, balance: Int) -> [(CBUUID, Data)] {
        switch gen {
        case .v3: return [BondGATT.v3Vibration(level: UInt8(level), balance: UInt8(balance))]
        case .v2, .v4, .mini: return [BondGATT.v2MotorStrength(level)]
        case .v1: return []
        }
    }

    private func userColorWrites(_ gen: BondGeneration, rgb: Int) -> [(CBUUID, Data)] {
        switch gen {
        case .v3: return []
        case .v2, .v4, .mini: return BondGATT.v2UserColor(gen, rgb: rgb)
        case .v1: return v1.userColor(rgb)
        }
    }

    private var v3Recording = BondGATT.V3Recording()
    private var v3FeaturesSent = false

    // Bond Touch More session state, reset on every connection (mirrors the original app's
    // BleBondManagerV3: `p` = firmware read, `o` = last bond state).
    private var v3FirmwareRead = false
    private var v3LastState: UInt8?
    private var slotsSynced = false
    /// The partner slots the bracelet should show — one colour per partner, up to three —
    /// and which bond each slot is. Set by the app from the partner list.
    private var desiredSlots: [BondGATT.V3Slot] = [.inactive, .inactive, .inactive]
    private var slotBondIDs: [String] = []

    /// Sets the bracelet's partner slots (colour per partner, up to 3, in order). Like the
    /// original app, a change is pushed to a paired Bond Touch More right away.
    func setPartnerMenu(_ partners: [(id: String, rgb: Int)]) {
        let top = Array(partners.prefix(3))
        slotBondIDs = top.map(\.id)
        let slots = top.map { BondGATT.V3Slot(state: .active, rgb: $0.rgb & 0xFFFFFF) }
            + Array(repeating: BondGATT.V3Slot.inactive, count: 3 - top.count)
        guard slots != desiredSlots else { return }
        desiredSlots = slots
        if gen == .v3, v3FirmwareRead { syncPartnerSlots() }
        else if gen == .v4, paired { enqueue(v4MenuWrites()) }
    }

    // MARK: - Bond Touch 4 partner menu (BleBondManagerV4)

    /// The slot the v4 sends to (the original's `p`), FIRST until told otherwise.
    private var v4Selected = 1
    private var v4MenuEnabled: Bool { desiredSlots[1].state == .active || desiredSlots[2].state == .active }

    /// A(): the three menu entries — slot 1 shows only once there's a second or third
    /// partner — then the selected slot, capped to the last active one (T()).
    private func v4MenuWrites() -> [(CBUUID, Data)] {
        func entry(_ i: Int, shown: Bool) -> (CBUUID, Data) {
            let s = desiredSlots[i]
            return BondGATT.v2MenuEntry(slot: i + 1, rgb: shown && s.state == .active ? s.rgb : nil)
        }
        return [entry(0, shown: v4MenuEnabled), entry(1, shown: true), entry(2, shown: true)]
            + v4SelectWrites(v4MenuIndex())
    }

    /// T(): the selected slot, no higher than the last active partner.
    private func v4MenuIndex() -> Int {
        let last = desiredSlots[2].state == .active ? 3 : desiredSlots[1].state == .active ? 2 : 1
        return min(last, v4Selected)
    }

    /// V(): SELECTED_USER, skipped while the menu isn't enabled.
    private func v4SelectWrites(_ slot: Int) -> [(CBUUID, Data)] {
        v4MenuEnabled ? [BondGATT.v2SelectedUser(slot)] : []
    }

    private func bondID(forSlot slot: Int) -> String? {
        slot >= 1 && slot <= slotBondIDs.count ? slotBondIDs[slot - 1] : nil
    }

    private var central: CBCentralManager!
    private var bracelet: CBPeripheral?
    private var gen: BondGeneration?
    private var chars: [CBUUID: CBCharacteristic] = [:]
    private var hasV3Service = false

    /// True when the connected bracelet is third-generation (BTM) — the original backend
    /// tags its touches generation "3"; every other model is "2".
    var isThirdGeneration: Bool { gen == .v3 }

    /// Persisted per-install AUID (device/user id) sent during pairing.
    private let auid: UInt32 = {
        let key = "BondAUID"
        let existing = UInt32(UserDefaults.standard.integer(forKey: key))
        if existing != 0 { return existing }
        let fresh = UInt32.random(in: 1...UInt32(Int32.max))
        UserDefaults.standard.set(Int(fresh), forKey: key)
        return fresh
    }()

    private var writeQueue: [(CBUUID, Data)] = []
    private var writing = false
    /// The write awaiting its response (to pause after a v2-base 0x32, as the original does).
    private var inFlight: (CBUUID, Data)?
    /// The original's command-queue pause: after a 0x32, while the bracelet records a message
    /// (v2-base 0x86, 15 s) or is busy (v1 247, 30 s). Lifted early by a CONNECTED state.
    private var queuePausedUntil: Date?
    private var queueResumeTimer: Timer?

    // Session state, reset on every connection. `paired` is the original's "device paired"
    // (listener j()): the settings go out once per connection when it's reached.
    private var paired = false
    private var servicesAwaitingChars = 0
    private var v2LastState: UInt8 = 0x00     // NO_STATE, as the original starts
    private var v2FirmwareRead = false
    /// A state read we asked for (the original's `k`): its answer doesn't re-arm the check.
    private var v2StateReadPending = false
    private var v2QueueCheck: Timer?
    private var v2Touch: [Int] = []
    private var v2TouchSlot = 0
    private var v1 = BondGATT.V1Commands()
    private var v1Started = false
    private var v1Touches: [(at: Int, count: Int, ms: Int)] = []

    private var heartbeatTimer: Timer?
    private var heartbeatWatchdog: Timer?
    private var heartbeatBPM = 0
    /// A Bond Touch More is glowing between heartbeat spikes.
    private var heartbeatGlow = false
    @Published private(set) var heartbeatActive = false

    /// CoreBluetooth's `connect` never times out, and service discovery / the pairing
    /// handshake can stall — so a connection can sit in "connecting" forever. This fires if
    /// we haven't reached `.connected` in time and recovers by cancelling and rescanning.
    private var connectWatchdog: Timer?
    private var connectAttempts = 0
    /// True from didConnect until didDisconnect — the radio link is up (the handshake may
    /// still be running). False while a pending connect is waiting for the bracelet.
    private var linkUp = false
    /// A touch that arrived while the bracelet was (re)connecting; played once it's back if
    /// still fresh, instead of being dropped.
    private var pendingPlay: (touch: TouchMessage, at: Date)?

    /// The bracelet this phone pairs with, remembered across launches. A pending connect to
    /// it by identifier is the only reconnect iOS completes in the background (a scan with no
    /// service filter returns nothing there), so we always prefer it over scanning.
    private static let savedIDKey = "BondBraceletID"
    private var savedID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.savedIDKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.savedIDKey) }
    }

    private var isForeground: Bool { UIApplication.shared.applicationState != .background }

    /// A bracelet found stuck in firmware-update (DFU) mode, waiting to be reflashed.
    struct DFUCandidate: Equatable {
        let id: UUID
        let model: BraceletModel
    }
    @Published var dfuDevice: DFUCandidate?

    override init() {
        super.init()
        // State restoration: if iOS ends the app in the background while the bracelet is
        // connected, it relaunches the app for the bracelet's events and hands the
        // connection back (centralManager(_:willRestoreState:)).
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "BondTouchBeyond.bracelet",
                                             CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: - Scan / connect

    func startScanning() {
        guard central.state == .poweredOn else { state = .bluetoothOff; return }
        userPaused = false

        // A bracelet already connected at the system level will not appear in a scan; ask
        // for it directly by its services, then by battery service filtered on name.
        var known = central.retrieveConnectedPeripherals(
            withServices: [BondGATT.serviceV3, BondGATT.serviceApp])
        if known.isEmpty {
            known = central.retrieveConnectedPeripherals(withServices: [BondGATT.batteryService])
                .filter { BondGATT.isBondName($0.name) }
        }
        if let peripheral = known.first {
            NetLog.shared.record(.send, "Bracelet: already connected to iOS — attaching")
            connect(peripheral); return
        }

        // Our own bracelet, by identifier: a pending connect completes the moment it's in
        // range — in the foreground or background — with no scan needed.
        if let id = savedID, let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first {
            NetLog.shared.record(.send, "Bracelet: reconnecting to saved bracelet")
            connect(peripheral)
            if isForeground { scanAll() }   // also look fresh, in case it shows up under a new id
            return
        }

        // The bracelet does not advertise its vendor service UUID — scan all and filter by name.
        NetLog.shared.record(.send, "Bracelet: scanning")
        state = .scanning
        scanAll()
    }

    private func scanAll() {
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func connect(_ peripheral: CBPeripheral) {
        if let old = bracelet, old != peripheral { central.cancelPeripheralConnection(old) }
        if bracelet != peripheral { connectStartedAt = Date() }
        bracelet = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        enterConnecting()
    }

    /// When we started trying to reach the current bracelet (to let a different one take over
    /// if the remembered one never answers).
    private var connectStartedAt: Date?
    /// Set by "Disconnect bracelet": don't reconnect on our own until Reconnect or a relaunch.
    private var userPaused = false

    /// The Settings "Disconnect bracelet" button: drop the link and stop auto-reconnecting.
    func disconnect() {
        clearConnectWatchdog()
        userPaused = true
        central.stopScan()
        let p = bracelet
        bracelet = nil          // so didDisconnect doesn't reconnect it straight back
        savedID = nil
        if let p { central.cancelPeripheralConnection(p) }
        resetConnectionState()
        state = .disconnected
    }

    /// Force a fresh connection attempt — for the Settings "Reconnect" button when it's stuck.
    /// Forgets the remembered bracelet so a new or reset one can be found.
    func reconnect() {
        clearConnectWatchdog()
        connectAttempts = 0
        dfuHandoff = false
        if let bracelet { central.cancelPeripheralConnection(bracelet) }
        bracelet = nil
        savedID = nil
        linkUp = false
        resetConnectionState()
        state = .disconnected
        startScanning()
    }

    // MARK: - Connection watchdog

    /// Enters the connecting state and arms the watchdog. Called whenever a connect is
    /// started (fresh connect, auto-reconnect, or state restoration).
    private func enterConnecting(timeout: TimeInterval = 15) {
        state = .connecting
        connectWatchdog?.invalidate()
        let t = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.connectTimedOut() }
        }
        RunLoop.main.add(t, forMode: .common)
        connectWatchdog = t
    }

    /// Reached a fully usable connection — clears the watchdog and resets the attempt count.
    private func markConnected() {
        clearConnectWatchdog()
        connectAttempts = 0
        let was = state
        state = .connected
        lastConnectedAt = Date()
        if let id = bracelet?.identifier { savedID = id }
        if was != .connected { NetLog.shared.record(.ok, "Bracelet connected", gen.map { "\($0)" } ?? "") }
        // A touch that came in while we were reconnecting: play it now if it's still fresh,
        // after a moment for the pairing handshake to settle.
        if let pending = pendingPlay {
            pendingPlay = nil
            if Date().timeIntervalSince(pending.at) < 120 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.play(pending.touch) }
            }
        }
    }

    private func clearConnectWatchdog() {
        connectWatchdog?.invalidate()
        connectWatchdog = nil
    }

    private func connectTimedOut() {
        guard state == .connecting, let p = bracelet else { return }
        connectAttempts += 1
        // Never give up on the bracelet: a pending connect is the only reconnect iOS completes
        // in the background. (The old watchdog cancelled it and fell back to a scan — which
        // returns nothing in the background — so one blip left the band dead until the app
        // was opened.)
        guard central.state == .poweredOn else { enterConnecting(timeout: 30); return }
        if linkUp {
            // The link is up but discovery / the handshake stalled: drop it. didDisconnect
            // re-issues the connect.
            NetLog.shared.record(.fail, "Bracelet handshake stalled — reconnecting", "attempt \(connectAttempts)")
            central.cancelPeripheralConnection(p)
        } else if isForeground {
            // Foreground, possibly a half-open attempt: cancel it, let any fresh discovery take
            // over at once, and re-issue the connect after a beat (a connect sent in the same
            // instant as a cancel can be swallowed).
            NetLog.shared.record(.fail, "Bracelet not answering — retrying", "attempt \(connectAttempts)")
            central.cancelPeripheralConnection(p)
            resetConnectionState()
            connectStartedAt = .distantPast
            scanAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.bracelet == p, !self.linkUp, self.state != .connected else { return }
                self.central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
            }
        } else {
            // Background, no link: make sure a pending connect really exists (one issued before
            // Bluetooth powered on is silently dropped) without cancelling it. Calling connect
            // on an already-pending peripheral is harmless.
            central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        }
        enterConnecting(timeout: min(15 * Double(connectAttempts + 1), 60))
    }

    // MARK: - Public actions

    /// Plays a received touch: replays the rhythm and glows/buzzes in its colour. Returns
    /// false if the bracelet isn't connected; then, with `holdIfOffline`, the touch is held and
    /// played when it's back (if still fresh).
    @discardableResult
    func play(_ touch: TouchMessage, holdIfOffline: Bool = true) -> Bool {
        guard let gen, state == .connected else {
            if holdIfOffline {
                pendingPlay = (touch, Date())
                NetLog.shared.record(.fail, "Bracelet not connected — touch held until it reconnects")
            }
            return false
        }
        // Into the slot of the partner it is from, so it shows in their colour.
        let slot = slotBondIDs.firstIndex(of: touch.bondID).map { $0 + 1 } ?? 1
        if gen == .v1 {
            enqueue(v1.touch(onOff: touch.onOffMs.isEmpty ? BondGATT.miniPattern : touch.onOffMs, rgb: touch.colorRGB))
        } else if touch.isRainbow, gen == .v3 {
            // A rainbow on the Bond Touch More: short pieces back to back, each its next hue.
            for piece in BondGATT.v3RainbowPieces(samples: touch.samples, slot: slot) {
                if piece.at == 0 { enqueue(piece.writes); continue }
                DispatchQueue.main.asyncAfter(deadline: .now() + piece.at) { [weak self] in
                    guard let self, self.gen == .v3 else { return }
                    self.enqueue(piece.writes)
                }
            }
        } else if touch.isRainbow, gen != .mini {
            enqueue(BondGATT.v2RainbowSteps(onOff: touch.onOffMs, strength: UInt8(clamping: vibrationLevel ?? 80)))
            if gen == .v4 { enqueue(v4SelectWrites(slot)) }
        } else {
            // v2-base plays it at the user's vibration strength (80 when unset, as the original).
            enqueue(BondGATT.touchSend(gen, touch: touch, slot: slot, strength: vibrationLevel ?? 80))
            // The Bond Touch 4 then selects that partner, so a reply goes back to them (V4.g).
            if gen == .v4 { enqueue(v4SelectWrites(slot)) }
        }
        lastPlayed = (touch, Date())
        return true
    }

    /// Called when a touch handed to the bracelet didn't make it (a write failed, or the link
    /// dropped right after) — so it can be played on the phone instead.
    var onPlayFailed: ((TouchMessage) -> Void)?
    private var lastPlayed: (touch: TouchMessage, at: Date)?

    private func reportPlayFailed(_ why: String) {
        guard let last = lastPlayed, Date().timeIntervalSince(last.at) < 5 else { return }
        lastPlayed = nil
        NetLog.shared.record(.fail, "Touch didn't reach the bracelet", why)
        onPlayFailed?(last.touch)
    }

    var isReady: Bool { state == .connected && gen != nil }

    /// Waits until every queued write has reached the bracelet (or `timeout` passes). Used
    /// before telling iOS a background wake is done, so it doesn't suspend the app mid-touch.
    @MainActor
    func waitUntilIdle(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while (writing || !writeQueue.isEmpty), bracelet != nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Plays a received heartbeat: one pulse per beat at `bpm` for `seconds` (5 s), then
    /// stops on its own.
    func playHeartbeat(bpm: Int, seconds: Double = 5, colorRGB: Int = 0xE85D75) {
        let clamped = min(max(bpm, 30), 220)
        stopHeartbeat()
        heartbeatBPM = clamped
        heartbeatActive = true
        let interval = 60.0 / Double(clamped)
        if gen == .v3 {
            // Bond Touch More: the band glows steadily between beats (light only, no motor);
            // each beat is a short spike up and down the bar, which is all that vibrates.
            // The glow is put back just after each spike has played.
            heartbeatGlow = true
            let beat: () -> Void = { [weak self] in
                guard let self, self.gen == .v3 else { return }
                self.enqueue(BondGATT.v3HeartbeatSpike(rgb: colorRGB))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self, self.heartbeatGlow else { return }
                    self.enqueue([BondGATT.v3Color(colorRGB)])
                }
            }
            enqueue([BondGATT.v3Color(colorRGB)])
            beat()
            let timer = Timer(timeInterval: interval, repeats: true) { _ in beat() }
            RunLoop.main.add(timer, forMode: .common)
            heartbeatTimer = timer
            let end = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.stopHeartbeat() }
            RunLoop.main.add(end, forMode: .common)
            heartbeatWatchdog = end
            return
        }
        if let gen { enqueue(heartbeatPulse(gen, rgb: colorRGB)) }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, let gen = self.gen else { return }
            self.enqueue(self.heartbeatPulse(gen, rgb: colorRGB))
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
        let end = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.stopHeartbeat() }
        RunLoop.main.add(end, forMode: .common)
        heartbeatWatchdog = end
    }

    func stopHeartbeat() {
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        heartbeatWatchdog?.invalidate(); heartbeatWatchdog = nil
        if heartbeatGlow {
            heartbeatGlow = false
            if gen == .v3 { enqueue([BondGATT.v3LedsOff]) }   // the glow goes out with the last beat
        }
        heartbeatBPM = 0
        heartbeatActive = false
    }

    private func heartbeatPulse(_ gen: BondGeneration, rgb: Int) -> [(CBUUID, Data)] {
        gen == .v1 ? v1.touch(onOff: [130], rgb: rgb) : BondGATT.heartbeatPulse(gen, rgb: rgb)
    }

    // MARK: - Light lab (debug)

    /// Which bracelet generation is connected (nil: none yet).
    var generation: BondGeneration? { gen }

    /// Writes raw frames in order (the debug Light lab).
    func send(_ writes: [(CBUUID, Data)]) { enqueue(writes) }

    // MARK: - Write queue

    private func enqueue(_ writes: [(CBUUID, Data)]) {
        writeQueue.append(contentsOf: writes)
        pump()
    }

    private func pump() {
        guard !writing, let bracelet, !writeQueue.isEmpty else { return }
        if let until = queuePausedUntil, until > Date() { return }
        let (uuid, data) = writeQueue[0]
        guard let char = chars[uuid] else { writeQueue.removeFirst(); pump(); return }
        if char.properties.contains(.write) {
            writing = true
            writeQueue.removeFirst()
            inFlight = (uuid, data)
            bracelet.writeValue(data, for: char, type: .withResponse)
        } else {
            guard bracelet.canSendWriteWithoutResponse else { return }
            writeQueue.removeFirst()
            bracelet.writeValue(data, for: char, type: .withoutResponse)
            didWrite(uuid, data)
            pump()
        }
    }

    /// The original pauses its queue 5 s once a v2-base 0x32 (end of a queued message) is
    /// written, until the bracelet reports CONNECTED again (BleBondManagerV2Base.b).
    private func didWrite(_ uuid: CBUUID, _ data: Data) {
        if gen?.usesV2Base == true, uuid == BondGATT.charAppCmd, data.first == 0x32 { pauseQueue(5) }
    }

    private func pauseQueue(_ seconds: TimeInterval) {
        queuePausedUntil = Date().addingTimeInterval(seconds)
        queueResumeTimer?.invalidate()
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.resumeQueue() }
        RunLoop.main.add(t, forMode: .common)
        queueResumeTimer = t
    }

    private func resumeQueue() {
        queueResumeTimer?.invalidate()
        queueResumeTimer = nil
        queuePausedUntil = nil
        pump()
    }

    // MARK: - Handshake

    private func sendToken() {
        guard let gen else { return }
        enqueue(BondGATT.tokenWrites(gen))
    }

    private func sendAuid() {
        guard let gen else { return }
        enqueue(BondGATT.auidWrites(gen, auid: auid))
    }

    /// The original's "device paired" (BleBondClient listener j()): the bracelet is usable;
    /// then, once per connection, the user's colour (f()), vibration (B()), partner menu
    /// (A()) and saved slot (s()), in that order.
    private func devicePaired() {
        markConnected()
        DispatchQueue.main.async { self.needsSetupTap = false }
        guard !paired, let gen else { return }
        paired = true
        if let rgb = userColor { enqueue(userColorWrites(gen, rgb: rgb)) }
        if let level = vibrationLevel { enqueue(vibrationWrites(gen, level: level, balance: vibrationBalance)) }
        switch gen {
        case .v3:
            syncPartnerSlots()
        case .v4:
            enqueue(v4MenuWrites())
            v4Selected = selectedSlot
            enqueue(v4SelectWrites(selectedSlot))
        default:
            break
        }
        if let p = bracelet, let model = chars[BondGATT.modelChar], model.properties.contains(.read) {
            p.readValue(for: model)
        }
    }

    // MARK: - v2 / v4 / mini session (the original app's BleBondManagerV2Base)

    /// As the original's constructor: read the battery (ff06) and enable notifications on
    /// it, the event channel (ffa5) and the state channel (ffa4); then a v2 sends the token
    /// right away (V2.I) and a v4/mini reads the state (V4/Mini.I). The bracelet is usable
    /// only once its firmware (2A26) has been read after it reports CONNECTED.
    private func startV2Base(_ p: CBPeripheral) {
        if let battery = chars[BondGATT.charFF06] {
            if battery.properties.contains(.read) { p.readValue(for: battery) }
            if battery.properties.contains(.notify) { p.setNotifyValue(true, for: battery) }
        }
        for uuid in [BondGATT.charEvent, BondGATT.charState] {
            if let c = chars[uuid] { p.setNotifyValue(true, for: c) }
        }
        if gen == .v2 { sendToken() } else { readV2State() }
    }

    private func readV2State() {
        guard let p = bracelet, let s = chars[BondGATT.charState], s.properties.contains(.read) else { return }
        v2StateReadPending = true
        p.readValue(for: s)
    }

    private func handleV2Base(_ uuid: CBUUID, _ data: Data) {
        switch uuid {
        case BondGATT.charState:
            let wasRead = v2StateReadPending
            v2StateReadPending = false
            if let s = BondGATT.V2State(data) { handleV2State(s, notified: !wasRead) }
        case BondGATT.charEvent:
            handleV2Event(BondGATT.v2Event(data))
        case BondGATT.charFF06:
            if data.count >= 2, let level = data.first { batteryPercent = min(Int(level), 100) }
        case BondGATT.firmwareChar:
            guard !v2FirmwareRead else { return }
            v2FirmwareRead = true
            let fw = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
            firmwareVersion = fw
            NetLog.shared.record(.ok, "Bracelet paired", "firmware \(fw)")
            checkFirmware()
            devicePaired()
            v2AfterPairing()
        default:
            break
        }
    }

    /// The original's onStateReadOrChanged (O()): charging, then each new bond state once.
    private func handleV2State(_ s: BondGATT.V2State, notified: Bool) {
        switch s.charging {
        case 0, 0xFF: charging = false
        case 1, 2:    charging = true
        default:      break
        }
        let known: [UInt8] = [0x00, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88]
        guard known.contains(s.bond) else { return }
        // QUEUE_EXECUTING notified: read the state again in 5 s to see whether it's still busy.
        if notified, s.bond == 0x88 {
            v2QueueCheck?.invalidate()
            let t = Timer(timeInterval: 5, repeats: false) { [weak self] _ in self?.readV2State() }
            RunLoop.main.add(t, forMode: .common)
            v2QueueCheck = t
        }
        guard s.bond != v2LastState else { return }
        v2LastState = s.bond
        if state != .connected { enterConnecting(timeout: 60) }   // handshake in progress
        switch s.bond {
        case 0x82:
            NetLog.shared.record(.send, "Bracelet: waiting for token — sending it")
            sendToken()
        case 0x83:
            NetLog.shared.record(.send, "Bracelet: waiting for id — sending it")
            sendAuid()
        case 0x84:
            NetLog.shared.record(.fail, "Bracelet is in setup mode — double-tap it to pair")
            DispatchQueue.main.async { self.needsSetupTap = true }
        case 0x85:
            // Connected, queue free: resume writes; the first time, read the firmware —
            // that answer is what makes the bracelet paired.
            v2QueueCheck?.invalidate(); v2QueueCheck = nil
            resumeQueue()
            guard !v2FirmwareRead else { return }
            if let p = bracelet, let fw = chars[BondGATT.firmwareChar], fw.properties.contains(.read) {
                p.readValue(for: fw)
            } else {
                // The original drops the connection here; we'd rather keep a usable bracelet.
                NetLog.shared.record(.fail, "Bracelet: no firmware characteristic (2A26)")
                v2FirmwareRead = true
                devicePaired()
                v2AfterPairing()
            }
        case 0x86:
            pauseQueue(15)                          // recording/playing a message
        default:
            break                                   // 0x00, 0x87 factory, 0x88 busy
        }
    }

    /// After the firmware read (the original's S()) and the OS bond (D()). v2: the bonded
    /// settings, ANCS off. v4/mini: ANCS off, then subscribe to the encrypted ffa8 — that
    /// makes iOS bond, and once it's on the bonded settings go out.
    private func v2AfterPairing() {
        guard let gen, gen.usesV2Base else { return }
        if gen == .v2 { enqueue(BondGATT.v2BondedSettings(gen)); return }
        enqueue([BondGATT.v2Ancs(false)])
        if let p = bracelet, let bond = chars[BondGATT.charBondNotify],
           bond.properties.contains(.notify) || bond.properties.contains(.indicate) {
            p.setNotifyValue(true, for: bond)
        } else {
            enqueue(BondGATT.v2BondedSettings(gen))
        }
    }

    private func handleV2Event(_ event: BondGATT.V2Event) {
        switch event {
        case .auidError:
            NetLog.shared.record(.fail, "Bracelet rejected this phone's id", "Double-tap the bracelet to pair it with this phone")
        case .pairedSignal:
            NetLog.shared.record(.send, "Bracelet: paired signal — confirming")
            enqueue([BondGATT.v2PairedReply])
        case .segment, .timeout:
            v2TouchReceived(event)
        case .tap:
            break                                   // the original only logs a single tap
        case .doubleTap:
            onDoubleTap?()
        case .ignored:
            break
        }
    }

    /// P(): v2/v4 assemble the on/off pattern from the segments (each ≥ 50 ms); the mini
    /// reports its fixed pattern for every touch event.
    private func v2TouchReceived(_ event: BondGATT.V2Event) {
        if gen == .mini { onLocalTap?(BondGATT.miniPattern, 2, nil); return }
        switch event {
        case .segment(let touchMs, let releaseMs, let counter, let stop, let slot):
            let on = max(touchMs, 50)
            if counter == 1 { v2Touch = [on]; v2TouchSlot = slot }
            else { v2Touch += [max(releaseMs, 50), on] }
            if stop { v2TouchEnded() }
        case .timeout(let counter, let slot):
            if counter == 0 { v2Touch = []; v2TouchSlot = slot }
            v2TouchEnded()
        default:
            break
        }
    }

    /// T() / U(): deliver the touch. A v4 touch is for the slot it was recorded in; if that
    /// isn't the selected one, the bracelet switched partner.
    private func v2TouchEnded() {
        let pattern = v2Touch
        v2Touch = []
        guard gen == .v4 else {
            if !pattern.isEmpty { onLocalTap?(pattern, 2, nil) }
            return
        }
        let slot = (1...3).contains(v2TouchSlot) ? v2TouchSlot : 1
        v2TouchSlot = 0
        if v4MenuIndex() != slot { reportSlotSelected(slot) }
        v4Selected = slot
        if !pattern.isEmpty { onLocalTap?(pattern, 2, bondID(forSlot: slot)) }
    }

    // MARK: - Classic v1 session (the original app's BleBondManagerV1)

    /// As the original: read the firmware (ff03), follow the battery (ff06); once the
    /// firmware is known, enable the event, state and command-result channels and send the
    /// token. The bracelet then asks for the AUID (244) and reports connected (246).
    private func startV1(_ p: CBPeripheral) {
        if let battery = chars[BondGATT.charFF06] {
            if battery.properties.contains(.notify) { p.setNotifyValue(true, for: battery) }
            if battery.properties.contains(.read) { p.readValue(for: battery) }
        }
        if let fw = chars[BondGATT.v1Firmware], fw.properties.contains(.read) { p.readValue(for: fw) }
        else { beginV1Handshake() }
    }

    private func beginV1Handshake() {
        guard !v1Started, let p = bracelet else { return }
        v1Started = true
        for uuid in [BondGATT.charEvent, BondGATT.charState, BondGATT.v1Ack] {
            if let c = chars[uuid] { p.setNotifyValue(true, for: c) }
        }
        sendToken()
    }

    private func handleV1(_ uuid: CBUUID, _ data: Data) {
        switch uuid {
        case BondGATT.v1Firmware:
            guard data.count >= 2 else { return }
            firmwareVersion = "1.\(data[data.startIndex + 1]).\(data[data.startIndex])"
            checkFirmware()
            beginV1Handshake()
        case BondGATT.charFF06:
            if let pct = BondGATT.v1BatteryPercent(data) { batteryPercent = pct }
        case BondGATT.charState:
            guard let s = BondGATT.V1State(data) else { return }
            if s.charging == 0 { charging = false } else if s.charging == 1 { charging = true }
            if state != .connected { enterConnecting(timeout: 60) }
            switch s.paired {
            case 244:
                NetLog.shared.record(.send, "Bracelet: waiting for id — sending it")
                sendAuid()
            case 246:
                resumeQueue()
                if !paired { NetLog.shared.record(.ok, "Bracelet paired", firmwareVersion.map { "firmware \($0)" } ?? "") }
                devicePaired()
            case 247:
                pauseQueue(30)
                onDoubleTap?()                      // as the original (listener l())
            default:
                break
            }
        case BondGATT.charEvent:
            guard let e = BondGATT.V1Event(data) else { return }
            switch e.id {
            case 18:
                NetLog.shared.record(.fail, "Bracelet rejected this phone's id", "Double-tap the bracelet to pair it with this phone")
            case 19:
                enqueue([BondGATT.v1PairedReply])
            case 20:
                v1TouchEvent(e)
            default:
                break
            }
        case BondGATT.v1Ack:
            let b = [UInt8](data)
            if b.count >= 2, (Int(b[0]) | Int(b[1]) << 8) != 1 {
                NetLog.shared.record(.fail, "Bracelet: command not accepted", "result \(Int(b[0]) | Int(b[1]) << 8)")
            }
        default:
            break
        }
    }

    /// BleTouchMessages: each segment arrives as it ends, with its press time; gaps come from
    /// the arrival times. Count 1 starts a touch, 0xFFFE (timeout) / 0xFFFF end it. Times are
    /// rounded to 50 ms.
    private func v1TouchEvent(_ e: BondGATT.V1Event) {
        let now = Int(ProcessInfo.processInfo.systemUptime * 1000)
        switch e.count {
        case 1:
            v1Touches = [(now, e.count, e.touchMs)]
        case 0xFFFE, 0xFFFF:
            func round50(_ x: Int) -> Int { Int((Double(x) / 50 + 0.5).rounded(.down)) * 50 }
            var pattern: [Int] = []
            for (i, m) in v1Touches.enumerated() {
                pattern.append(round50(m.ms))
                if i < v1Touches.count - 1 {
                    let next = v1Touches[i + 1]
                    let gap = next.at - next.ms - m.at
                    pattern.append(round50(gap < 0 ? 100 : gap))
                }
            }
            v1Touches = []
            if !pattern.isEmpty { onLocalTap?(pattern, 2, nil) }
        default:
            v1Touches.append((now, e.count, e.touchMs))
        }
    }

    // MARK: - Bond Touch More session (the original app's BleBondManagerV3, step for step)

    /// Every FFB1 notification from a Bond Touch More: system states, bond events, the
    /// firmware answer and command acks.
    private func handleV3(_ data: Data) {
        let b = [UInt8](data)
        guard let kind = b.first else { return }
        switch kind {
        case 0x04 where b.count >= 2:                              // system state
            let s = b[1]
            guard s != v3LastState else { return }                 // the original ignores repeats
            v3LastState = s
            if state != .connected { enterConnecting(timeout: 60) } // handshake in progress
            switch s {
            case 130:
                NetLog.shared.record(.send, "Bracelet: waiting for token — sending it")
                sendToken()
            case 131:
                NetLog.shared.record(.send, "Bracelet: waiting for id — sending it")
                sendAuid()
            case 132:
                NetLog.shared.record(.fail, "Bracelet is in setup mode", "Double-tap the bracelet to pair it with this phone")
                DispatchQueue.main.async { self.needsSetupTap = true }
            case 133:
                NetLog.shared.record(.ok, "Bracelet: handshake complete")
                if !v3FirmwareRead, !v3FeaturesSent {
                    v3FeaturesSent = true
                    enqueue(BondGATT.v3ConnectedWrites)
                }
                enableV3TouchNotifications()
                markConnected()
            case 138:
                NetLog.shared.record(.send, "Bracelet: confirming pairing")
                enqueue([BondGATT.v3PairedConfirm])
            default:
                break
            }
        case 0x02 where b.count >= 2:                              // bond events
            switch b[1] {
            case 19:                                               // APP_EVENT_PAIRED_SIGNAL
                NetLog.shared.record(.send, "Bracelet: paired signal — confirming")
                enqueue([BondGATT.v3PairedConfirm])
            case 178:                                              // EVENT_NO_ACTION_DOUBLE_TAP_DETECTED
                onDoubleTap?()
            case 180 where b.count >= 3 && (1...3).contains(b[2]): // EVENT_USER_SELECTED [index]
                reportSlotSelected(Int(b[2]))
            default:
                break
            }
        case 0xAC where b.count >= 4:                              // firmware [minor, major, generation]
            guard !v3FirmwareRead else { return }
            v3FirmwareRead = true
            firmwareVersion = "\(b[3]).\(b[2]).\(b[1])"
            NetLog.shared.record(.ok, "Bracelet paired", "firmware \(b[3]).\(b[2]).\(b[1])")
            checkFirmware()
            enableV3TouchNotifications()
            if let p = bracelet, let battery = chars[BondGATT.batteryLevel] {
                if battery.properties.contains(.read) { p.readValue(for: battery) }
                if battery.properties.contains(.notify) { p.setNotifyValue(true, for: battery) }
            }
            devicePaired()                                         // then the settings, as the original
        case 0x0A where b.count >= 2:                              // command acks
            switch b[1] {
            case 0x45:
                if let current = BondGATT.v3UserColors(fromAck: b) { reconcileSlots(current) }
            case 0x48 where b.count >= 4:
                // As the original: if the bracelet's vibration isn't the user's, send it again.
                if let level = vibrationLevel, Int(b[2]) != level || Int(b[3]) != vibrationBalance {
                    enqueue([BondGATT.v3Vibration(level: UInt8(level), balance: UInt8(vibrationBalance))])
                }
            case 0x49:
                if let alert = BondGATT.BatteryAlertSettings(v3Ack: b) { batteryAlert = alert }
            default:
                break
            }
        default:
            break
        }
    }

    /// FFB2 carries touches made on the bar; the original enables it once paired.
    private func enableV3TouchNotifications() {
        guard let p = bracelet, let ffb2 = chars[BondGATT.ffb2],
              ffb2.properties.contains(.notify), !ffb2.isNotifying else { return }
        p.setNotifyValue(true, for: ffb2)
    }

    /// As the original: ask the bracelet for its partner slots; the ack is answered with a
    /// write of only the slots that differ. If no ack comes, write them outright.
    private func syncPartnerSlots() {
        slotsSynced = false
        enqueue([BondGATT.v3ReadUserColors])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.gen == .v3, self.linkUp, !self.slotsSynced else { return }
            self.slotsSynced = true
            self.enqueue([BondGATT.v3WriteUserColors(self.desiredSlots)])
            NetLog.shared.record(.send, "Bracelet: partner colours written")
        }
    }

    private func reconcileSlots(_ current: [BondGATT.V3Slot]) {
        slotsSynced = true
        var out: [BondGATT.V3Slot] = []
        var changed = false
        for (i, want) in desiredSlots.enumerated() {
            if i < current.count, current[i] == want {
                out.append(BondGATT.V3Slot(state: .ignore, rgb: want.rgb))   // leave as is
            } else {
                out.append(want)
                changed = true
            }
        }
        guard changed else { return }
        enqueue([BondGATT.v3WriteUserColors(out)])
        NetLog.shared.record(.send, "Bracelet: partner colours updated")
    }
}

extension BraceletManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if userPaused { return }
            if let p = bracelet, !linkUp, p.state != .connected {
                // A bracelet restored by iOS (or one we were reaching before Bluetooth went off):
                // connects only work once powered on, so (re)issue it now.
                central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
                enterConnecting()
                if isForeground { scanAll() }
            } else if state == .disconnected || state == .bluetoothOff {
                startScanning()
            }
        case .poweredOff:
            state = .bluetoothOff
        default:
            state = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        // A bracelet stuck in update mode: never connect to it as a bracelet; offer recovery.
        if let model = BondGATT.dfuModel(advName) {
            if dfuDevice?.id != peripheral.identifier {
                dfuDevice = DFUCandidate(id: peripheral.identifier, model: model)
            }
            return
        }
        // Restarting in update mode: the updater takes it from here.
        guard BondGATT.isBondName(advName), !userPaused, !dfuHandoff else { return }
        // Already connecting to this one (e.g. the pending connect to our saved bracelet).
        if peripheral == bracelet, state == .connecting || state == .connected { return }
        if let current = bracelet, current != peripheral {
            // Prefer the bracelet we're already reaching — but if it hasn't answered in 10 s
            // (e.g. it was reset and now shows up under a new identifier), take this one.
            // A partner's bracelet connected to their phone doesn't advertise, so this won't
            // grab theirs.
            if state == .connected { return }
            if let started = connectStartedAt, Date().timeIntervalSince(started) < 10 { return }
            NetLog.shared.record(.send, "Bracelet: saved one isn't answering — switching to \(advName ?? "bracelet")")
        }
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let p = peripherals.first(where: { BondGATT.isBondName($0.name) }) ?? peripherals.first else { return }
        bracelet = p
        p.delegate = self
        if p.state == .connected {
            linkUp = true
            resetConnectionState()
            enterConnecting()
            p.discoverServices(nil)
        } else {
            // Not connected: the connect is issued in centralManagerDidUpdateState once
            // Bluetooth is powered on (a connect before that is silently dropped).
            linkUp = false
            connectStartedAt = Date()
            state = .connecting
        }
    }

    /// Stops looking for a bracelet (the firmware updater takes over the radio for a minute).
    func pauseScanning() {
        central.stopScan()
    }

    /// After a reflash: forget the DFU device and look for the bracelet again.
    func resumeAfterRecovery() {
        dfuHandoff = false
        dfuDevice = nil
        state = .disconnected
        startScanning()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        linkUp = true
        central.stopScan()
        resetConnectionState()
        // A fresh window for discovery + the pairing handshake — long enough for an iOS
        // "Bluetooth Pairing Request" to be answered. Each state the bracelet reports extends it.
        enterConnecting(timeout: 30)
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        linkUp = false
        resetConnectionState()
        NetLog.shared.record(.fail, "Bracelet connect failed — retrying", error?.localizedDescription ?? "")
        guard peripheral == bracelet else { state = .disconnected; startScanning(); return }
        // Keep a pending connect alive (a scan wouldn't work in the background); a short
        // pause so an instant failure can't spin the radio.
        state = .connecting
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.bracelet == peripheral, !self.linkUp else { return }
            self.central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
            self.enterConnecting()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        if state == .connected { lastConnectedAt = Date() }   // connected right up to now
        linkUp = false
        state = .disconnected
        resetConnectionState()
        reportPlayFailed("bracelet disconnected")
        if error != nil { NetLog.shared.record(.fail, "Bracelet disconnected — reconnecting", error?.localizedDescription ?? "") }
        // Reconnect automatically (also in the background): a pending connect completes
        // whenever the bracelet comes back in range. Not while it restarts in update mode —
        // the updater connects to it then.
        if peripheral == bracelet, !dfuHandoff {
            central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
            enterConnecting()
        }
        // In the foreground, also scan so a bracelet that rebooted into update mode is noticed
        // (an unfiltered scan returns nothing in the background).
        if isForeground { scanAll() }
    }

    private func resetConnectionState() {
        gen = nil
        v3FeaturesSent = false
        v3FirmwareRead = false
        v3LastState = nil
        slotsSynced = false
        v3Recording = BondGATT.V3Recording()
        chars.removeAll()
        hasV3Service = false
        writeQueue.removeAll()
        writing = false
        inFlight = nil
        queueResumeTimer?.invalidate(); queueResumeTimer = nil
        queuePausedUntil = nil
        paired = false
        servicesAwaitingChars = 0
        v2LastState = 0x00
        v2FirmwareRead = false
        v2StateReadPending = false
        v2QueueCheck?.invalidate(); v2QueueCheck = nil
        v2Touch = []
        v2TouchSlot = 0
        v4Selected = 1
        v1 = BondGATT.V1Commands()
        v1Started = false
        v1Touches = []
    }

    /// The generation is known: start its session as the original's manager does.
    private func startSession(_ p: CBPeripheral) {
        guard let gen else { return }
        switch gen {
        case .v1: startV1(p)
        case .v2, .v4, .mini: startV2Base(p)
        case .v3: break
        }
    }
}

extension BraceletManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        hasV3Service = services.contains { $0.uuid == BondGATT.serviceV3 }
        servicesAwaitingChars = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for char in service.characteristics ?? [] {
            chars[char.uuid] = char
        }
        servicesAwaitingChars = max(0, servicesAwaitingChars - 1)

        // Battery level (standard battery service): read it now and follow changes. (A Bond
        // Touch More's battery is read once it's paired, as the original app does.)
        if !hasV3Service, service.uuid == BondGATT.batteryService, let battery = chars[BondGATT.batteryLevel] {
            if battery.properties.contains(.read) { peripheral.readValue(for: battery) }
            if battery.properties.contains(.notify) { peripheral.setNotifyValue(true, for: battery) }
        }

        if hasV3Service {
            // Bond Touch More, as the original app: enable FFB1 notifications; once they're on
            // (didUpdateNotificationStateFor) ask for the firmware version, and answer the
            // bracelet's state notifications (handleV3). FFB2 is enabled once it's paired.
            if gen == nil, let ffb1 = chars[BondGATT.ffb1] {
                gen = .v3
                peripheral.setNotifyValue(true, for: ffb1)
            }
        } else if gen == nil, servicesAwaitingChars == 0 {
            // Non-v3, every service's characteristics known (the session needs chars from
            // several services): read the API-version byte to pick the generation.
            if let apiChar = chars[BondGATT.charApiVer], apiChar.properties.contains(.read) {
                peripheral.readValue(for: apiChar)
            } else if chars[BondGATT.charEvent] != nil {
                // App service present but no readable version char — default to the v2 base.
                gen = .v2
                startSession(peripheral)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }

        if characteristic.uuid == BondGATT.batteryLevel, let level = data.first {
            batteryPercent = min(Int(level), 100)
            return
        }

        if characteristic.uuid == BondGATT.charApiVer, gen == nil {
            let version = data.first
            let detected = BondGATT.generation(hasV3Service: false, apiVersion: version)
            gen = detected
            NetLog.shared.record(.send, "Bracelet: generation \(detected)", version.map { String(format: "API 0x%02X", $0) } ?? "")
            startSession(peripheral)
            return
        }

        if characteristic.uuid == BondGATT.modelChar {
            modelNumber = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
            return
        }

        guard let gen else { return }
        switch gen {
        case .v3:
            if characteristic.uuid == BondGATT.ffb2 {
                // A touch made on the bar, for the partner in its slot.
                if let touch = v3Recording.feed(data) { onLocalTap?(touch.samples, 3, bondID(forSlot: touch.slot)) }
                return
            }
            if characteristic.uuid == BondGATT.ffb1 { handleV3(data); return }
        case .v1:
            handleV1(characteristic.uuid, data)
        case .v2, .v4, .mini:
            handleV2Base(characteristic.uuid, data)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            NetLog.shared.record(.fail, "Bracelet: couldn't enable notifications", error.localizedDescription)
            return
        }
        // Bond Touch 4 / mini: the encrypted ffa8 is on, so iOS has bonded with the bracelet —
        // the original writes its bonded settings at this point (D()).
        if characteristic.uuid == BondGATT.charBondNotify, characteristic.isNotifying,
           let gen, gen == .v4 || gen == .mini {
            enqueue(BondGATT.v2BondedSettings(gen))
            return
        }
        // Bond Touch More: FFB1 notifications are on — ask for the firmware version, as the
        // original does; ask once more after 3 s if it hasn't answered.
        guard gen == .v3, characteristic.uuid == BondGATT.ffb1, characteristic.isNotifying else { return }
        enqueue([BondGATT.v3FirmwareRequest])
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.gen == .v3, self.linkUp, !self.v3FirmwareRead else { return }
            self.enqueue([BondGATT.v3FirmwareRequest])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        writing = false
        let wrote = inFlight
        inFlight = nil
        if let error { reportPlayFailed(error.localizedDescription) }
        else {
            if let wrote { didWrite(wrote.0, wrote.1) }
            if writeQueue.isEmpty { lastPlayed = nil }   // the touch fully reached the bracelet
        }
        pump()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        pump()
    }
}
