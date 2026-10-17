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
    /// Battery percentage from the standard Bluetooth battery service (last known value).
    @Published private(set) var batteryPercent: Int?
    /// When the bracelet was last connected (now, while it is), kept across launches.
    @Published private(set) var lastConnectedAt: Date? =
        UserDefaults.standard.object(forKey: "BondBraceletLastConnected") as? Date {
        didSet { UserDefaults.standard.set(lastConnectedAt, forKey: "BondBraceletLastConnected") }
    }
    /// Delivered when the user makes a touch on their own bracelet: the pattern and its
    /// generation (3 = Bond Touch More position samples, 2 = on/off milliseconds).
    var onLocalTap: (([Int], Int) -> Void)?
    private var v3Recording = BondGATT.V3Recording()
    private var v3FeaturesSent = false

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

    private var incoming: [Int] = []

    private var heartbeatTimer: Timer?
    private var heartbeatWatchdog: Timer?
    private var heartbeatBPM = 0
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
        enqueue(BondGATT.touchSend(gen, touch: touch))
        // The Bond Touch More renders the touch itself (LEDs + panned vibration); older
        // bracelets also get a glow + buzz in the touch's colour.
        if gen != .v3 { enqueue(BondGATT.ledMotor(gen, rgb: touch.colorRGB)) }
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

    /// Plays a received heartbeat: one pulse per beat at `bpm` for `seconds` (5 s), then
    /// stops on its own.
    func playHeartbeat(bpm: Int, seconds: Double = 5, colorRGB: Int = 0xE85D75) {
        let clamped = min(max(bpm, 30), 220)
        stopHeartbeat()
        heartbeatBPM = clamped
        heartbeatActive = true
        let interval = 60.0 / Double(clamped)
        if gen == .v3 {
            // The Bond Touch More plays the whole heartbeat itself, light + vibration in sync.
            enqueue(BondGATT.v3Heartbeat(bpm: clamped, seconds: seconds, rgb: colorRGB))
            let end = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.stopHeartbeat() }
            RunLoop.main.add(end, forMode: .common)
            heartbeatWatchdog = end
            return
        }
        if let gen { enqueue(BondGATT.heartbeatPulse(gen, rgb: colorRGB)) }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, let gen = self.gen else { return }
            self.enqueue(BondGATT.heartbeatPulse(gen, rgb: colorRGB))
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
        heartbeatBPM = 0
        heartbeatActive = false
    }

    // MARK: - Write queue

    private func enqueue(_ writes: [(CBUUID, Data)]) {
        writeQueue.append(contentsOf: writes)
        pump()
    }

    private func pump() {
        guard !writing, let bracelet, !writeQueue.isEmpty else { return }
        let (uuid, data) = writeQueue[0]
        guard let char = chars[uuid] else { writeQueue.removeFirst(); pump(); return }
        if char.properties.contains(.write) {
            writing = true
            writeQueue.removeFirst()
            bracelet.writeValue(data, for: char, type: .withResponse)
        } else {
            guard bracelet.canSendWriteWithoutResponse else { return }
            writeQueue.removeFirst()
            bracelet.writeValue(data, for: char, type: .withoutResponse)
            pump()
        }
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

    private func handle(_ signal: BondSignal) {
        switch signal {
        case .waitingToken: sendToken()
        case .waitingAuid:  sendAuid()
        case .connected:
            markConnected()
            if gen == .v3, !v3FeaturesSent {
                v3FeaturesSent = true
                enqueue(BondGATT.v3ConnectedWrites)
            }
        case .other:        break
        }
    }

    private func handle(_ event: BondGATT.TouchEvent) {
        switch event {
        case .segment(let touchMs, let releaseMs, let counter, let stop):
            if counter <= 1 { incoming = [max(touchMs, 50)] }
            else { incoming.append(max(releaseMs, 50)); incoming.append(max(touchMs, 50)) }
            if stop {
                let pattern = incoming
                incoming = []
                if !pattern.isEmpty { onLocalTap?(pattern, 2) }
            }
        case .tap:
            onLocalTap?([120], 2)
        case .doubleTap:
            onLocalTap?([120, 120, 120], 2)
        case .ignored:
            break
        }
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
        guard BondGATT.isBondName(advName), !userPaused else { return }
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
        dfuDevice = nil
        state = .disconnected
        startScanning()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        linkUp = true
        central.stopScan()
        resetConnectionState()
        enterConnecting()            // fresh window for discovery + the pairing handshake
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
        // whenever the bracelet comes back in range.
        if peripheral == bracelet {
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
        chars.removeAll()
        hasV3Service = false
        incoming = []
        writeQueue.removeAll()
        writing = false
    }
}

extension BraceletManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        hasV3Service = services.contains { $0.uuid == BondGATT.serviceV3 }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for char in service.characteristics ?? [] {
            chars[char.uuid] = char
        }

        // Battery level (standard battery service): read it now and follow changes.
        if service.uuid == BondGATT.batteryService, let battery = chars[BondGATT.batteryLevel] {
            if battery.properties.contains(.read) { peripheral.readValue(for: battery) }
            if battery.properties.contains(.notify) { peripheral.setNotifyValue(true, for: battery) }
        }

        if hasV3Service {
            // v3: subscribe FFB1 (events/state) and FFB2, then drive the handshake.
            if let ffb1 = chars[BondGATT.ffb1] { peripheral.setNotifyValue(true, for: ffb1) }
            if let ffb2 = chars[BondGATT.ffb2], ffb2.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: ffb2)
            }
            if gen == nil, chars[BondGATT.ffb1] != nil {
                // The original app sends nothing here: it answers the bracelet's own state
                // notifications (waiting for token → token, waiting for AUID → AUID,
                // connected → feature enables).
                gen = .v3
                markConnected()
            }
        } else if gen == nil, let apiChar = chars[BondGATT.charApiVer],
                  apiChar.properties.contains(.read) {
            // Non-v3: read the API-version byte to pick the generation.
            peripheral.readValue(for: apiChar)
        } else if gen == nil, chars[BondGATT.charEvent] != nil, chars[BondGATT.charApiVer] == nil {
            // App service present but no readable version char — default to the v2 base.
            gen = .v2
            subscribeV2Base(peripheral)
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
            gen = BondGATT.generation(hasV3Service: false, apiVersion: version)
            subscribeV2Base(peripheral)
            return
        }

        guard let gen else { return }
        if gen == .v3, characteristic.uuid == BondGATT.ffb2 {
            if let samples = v3Recording.feed(data) { onLocalTap?(samples, 3) }
            return
        }
        handle(BondGATT.signal(gen, uuid: characteristic.uuid, data: data))
        handle(BondGATT.touchEvent(gen, uuid: characteristic.uuid, data: data))
    }

    private func subscribeV2Base(_ peripheral: CBPeripheral) {
        if let stateChar = chars[BondGATT.charState] { peripheral.setNotifyValue(true, for: stateChar) }
        if let eventChar = chars[BondGATT.charEvent] { peripheral.setNotifyValue(true, for: eventChar) }
        markConnected()
        // Like the original app, the token and AUID are sent only when the bracelet asks
        // for them on its state channel (handled in handle(_ signal:)).
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        writing = false
        if let error { reportPlayFailed(error.localizedDescription) }
        else if writeQueue.isEmpty { lastPlayed = nil }   // the touch fully reached the bracelet
        pump()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        pump()
    }
}
