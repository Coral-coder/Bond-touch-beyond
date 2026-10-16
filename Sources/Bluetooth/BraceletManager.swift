import CoreBluetooth
import Foundation

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
    /// Delivered when the user makes a touch on their own bracelet: the pattern and its
    /// generation (3 = Bond Touch More position samples, 2 = on/off milliseconds).
    var onLocalTap: (([Int], Int) -> Void)?
    private var v3Recording = BondGATT.V3Recording()

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

        // A bracelet already connected at the system level will not appear in a scan; ask
        // for it directly by its services, then by battery service filtered on name.
        var known = central.retrieveConnectedPeripherals(
            withServices: [BondGATT.serviceV3, BondGATT.serviceApp])
        if known.isEmpty {
            known = central.retrieveConnectedPeripherals(withServices: [BondGATT.batteryService])
                .filter { BondGATT.isBondName($0.name) }
        }
        if let peripheral = known.first { connect(peripheral); return }

        // The bracelet does not advertise its vendor service UUID — scan all and filter by name.
        state = .scanning
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func connect(_ peripheral: CBPeripheral) {
        if let old = bracelet, old != peripheral { central.cancelPeripheralConnection(old) }
        bracelet = peripheral
        peripheral.delegate = self
        state = .connecting
        central.stopScan()
        central.connect(peripheral)
    }

    func disconnect() {
        if let bracelet { central.cancelPeripheralConnection(bracelet) }
    }

    // MARK: - Public actions

    /// Plays a received touch: replays the rhythm and glows/buzzes in its colour.
    func play(_ touch: TouchMessage) {
        guard let gen else { return }
        enqueue(BondGATT.touchSend(gen, touch: touch))
        // The Bond Touch More renders the touch itself (LEDs + panned vibration); older
        // bracelets also get a glow + buzz in the touch's colour.
        if gen != .v3 { enqueue(BondGATT.ledMotor(gen, rgb: touch.colorRGB)) }
    }

    /// Plays a received heartbeat: one pulse per beat at `bpm` for `seconds` (10 s), then
    /// stops on its own.
    func playHeartbeat(bpm: Int, seconds: Double = 10, colorRGB: Int = 0xE85D75) {
        let clamped = min(max(bpm, 30), 220)
        stopHeartbeat()
        heartbeatBPM = clamped
        heartbeatActive = true
        let interval = 60.0 / Double(clamped)
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
        case .connected:    state = .connected
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
            if state == .disconnected || state == .bluetoothOff { startScanning() }
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
        guard BondGATT.isBondName(advName) else { return }
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let p = peripherals.first(where: { BondGATT.isBondName($0.name) }) ?? peripherals.first else { return }
        bracelet = p
        p.delegate = self
        if p.state == .connected {
            state = .connecting
            resetConnectionState()
            p.discoverServices(nil)
        } else {
            state = .connecting
            central.connect(p)
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
        resetConnectionState()
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        state = .disconnected
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        state = .disconnected
        resetConnectionState()
        // Reconnect automatically (also in the background): a pending connect completes
        // whenever the bracelet comes back in range.
        if peripheral == bracelet { state = .connecting; central.connect(peripheral) }
        // Keep scanning meanwhile so a bracelet that rebooted into update mode is noticed.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func resetConnectionState() {
        gen = nil
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

        if hasV3Service {
            // v3: subscribe FFB1 (events/state) and FFB2, then drive the handshake.
            if let ffb1 = chars[BondGATT.ffb1] { peripheral.setNotifyValue(true, for: ffb1) }
            if let ffb2 = chars[BondGATT.ffb2], ffb2.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: ffb2)
            }
            if gen == nil, chars[BondGATT.ffb1] != nil {
                gen = .v3
                state = .connected
                sendToken(); sendAuid()
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
        state = .connected
        // Proactively begin the handshake; the bracelet also prompts via its state channel.
        sendToken(); sendAuid()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        writing = false
        pump()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        pump()
    }
}
