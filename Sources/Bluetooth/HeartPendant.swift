import CoreBluetooth
import Foundation

/// The Bond Heart pendant's GATT layout and commands (BLE_PROTOCOL.md §2), as the original
/// app's `HeartBleManager` uses them.
enum HeartGATT {
    static let service = CBUUID(string: "014F0A00-02CD-4DD4-842D-39FDFABC66F9")
    /// Notify: state / events / acknowledgements. Write: the heartbeat pattern (savePattern).
    static let notify = CBUUID(string: "014FFA01-02CD-4DD4-842D-39FDFABC66F9")
    /// Write: commands (token, AUID, paired signal, firmware read, setting).
    static let command = CBUUID(string: "014FFA02-02CD-4DD4-842D-39FDFABC66F9")
    /// Read (encrypted — iOS pairs on the first read): played / beats counters.
    static let count = CBUUID(string: "014FFA03-02CD-4DD4-842D-39FDFABC66F9")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    static let name = "BondHeart"
    static let dfuName = "BOND_H_DFU"

    static func isPendantName(_ name: String?) -> Bool {
        name?.uppercased().hasPrefix("BONDHEART") == true
    }

    /// `sendToken`: 0x09 + ASCII "76543210".
    static let token: [UInt8] = [0x09, 0x37, 0x36, 0x35, 0x34, 0x33, 0x32, 0x31, 0x30]
    /// `sendPairedSignal`, the answer to the PAIRED_SIG event.
    static let pairedSignal: [UInt8] = [0x07, 0x31]
    /// `readFirmwareVersion`: the pendant answers with acknowledgement 28 on `notify`.
    static let readFirmware: [UInt8] = [0x1C, 0x31]
    /// `setSetting` — sent by the original, meaning unknown; not used here.
    static let setting: [UInt8] = [0x10, 0x33]

    /// `sendAuid`: 0x0A + the app's persisted random id as u32 little-endian, 9 bytes.
    static func auid(_ value: UInt32) -> [UInt8] {
        [0x0A, UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
         UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF), 0, 0, 0, 0]
    }

    /// `savePattern`: 0x01 + up to 19 inter-beat intervals, each `((ms - 260) * 255) / 1280`
    /// as a byte (260 ms → 0, 1540 ms → 255). Like the original, the last interval is left
    /// out (`subList(0, min(19, size - 1))`). Out-of-range values are clamped here (the
    /// original would wrap them).
    static func pattern(_ intervals: [Int]) -> [UInt8] {
        let n = max(0, min(19, intervals.count - 1))
        return [0x01] + intervals.prefix(n).map { ms in
            UInt8(clamping: min(255, max(0, ((ms - 260) * 255) / 1280)))
        }
    }

    /// The firmware the original treats as current (older ones get a DFU prompt) and the
    /// oldest it supports.
    static let currentFirmware = HeartFirmware(major: 1, minor: 0, patch: 3, build: 10)
    static let minimumFirmware = HeartFirmware(major: 1, minor: 0, patch: 2, build: 0)
}

struct HeartFirmware: Comparable, Equatable {
    let major: Int, minor: Int, patch: Int, build: Int
    var text: String { "\(major).\(minor).\(patch).\(build)" }
    private var parts: [Int] { [major, minor, patch, build] }
    static func < (a: HeartFirmware, b: HeartFirmware) -> Bool { a.parts.lexicographicallyPrecedes(b.parts) }
}

/// What the pendant reports in a state frame (`[0x01, state]`).
enum HeartPeripheralState: UInt8 {
    case waitingToken = 130, waitingAuid = 131, oobe = 132, connected = 133
}

/// What the pendant reports in an event frame (`[0x02, event]`).
enum HeartEvent: UInt8 {
    case pairedSignal = 19, timeout = 20, wrongToken = 21, unsupportedMessage = 22, noAuth = 23
    case factoryButtonPressed = 24, factoryButtonReleased = 25, factoryShakeDetected = 26

    var text: String {
        switch self {
        case .pairedSignal: return "Paired"
        case .timeout: return "The Heart timed out — wake it and try again."
        case .wrongToken: return "The Heart refused the app's token."
        case .unsupportedMessage: return "The Heart didn't understand a command."
        case .noAuth: return "The Heart isn't paired with this phone."
        case .factoryButtonPressed, .factoryButtonReleased, .factoryShakeDetected: return "Factory test event"
        }
    }
}

/// The pendant's connection state, modelled on the original's `HeartBleManagerState`
/// (Authentication, Oobe, Connected, DfuNeeded, BatteryNeeded) plus the link states.
enum HeartState: Equatable {
    case bluetoothOff, unauthorized
    /// No pendant paired, not looking for one.
    case idle
    /// Looking for the pendant (pairing, or waiting for the saved one to wake).
    case searching
    case connecting
    /// Token / AUID handshake in progress.
    case authenticating
    /// The pendant is waiting to be paired: double-tap it (it sends PAIRED_SIG).
    case oobe
    case connected
    /// Works, but its firmware is older than the original app's current one.
    case dfuNeeded
    /// Old firmware and under 50 % battery: the original asks to charge before updating.
    case needsBattery
    /// The pendant is in its bootloader (advertising BOND_H_DFU).
    case dfuMode

    var text: String {
        switch self {
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth access is off for this app"
        case .idle: return "Heart not paired"
        case .searching: return "Searching for Heart"
        case .connecting: return "Connecting…"
        case .authenticating: return "Pairing…"
        case .oobe: return "Double-tap your Heart"
        case .connected: return "Connected"
        case .dfuNeeded: return "Connected — firmware update available"
        case .needsBattery: return "Connected — battery low"
        case .dfuMode: return "Heart is in update mode"
        }
    }

    /// Ready for patterns and counter reads.
    var isUsable: Bool { self == .connected || self == .dfuNeeded || self == .needsBattery }
}

struct HeartCounts: Equatable {
    /// u32 LE at offset 0: what the original stores as the heartbeat's played ("felt") count.
    let played: Int
    /// u32 LE at offset 4: what the original logs as "beats count".
    let beats: Int
}

enum HeartPendantError: LocalizedError {
    case notConnected, tooShort, timeout, failed(String)
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Your Heart isn't connected. Wake it (hold and tap until it flashes) and keep it near your phone."
        case .tooShort: return "This heartbeat is too short to wear."
        case .timeout: return "Your Heart didn't answer."
        case .failed(let s): return s
        }
    }
}

/// CoreBluetooth central for the Bond Heart pendant — separate from the bracelet's
/// (`BraceletManager`), with its own restore identifier.
///
/// Flow, as the original: scan for "BondHeart" → connect → subscribe to `notify` and the
/// battery level → the pendant reports its state: WAITING_TOKEN → send the token then the
/// AUID; WAITING_AUID → send the AUID; OOBE → the user double-taps it, it sends PAIRED_SIG,
/// we answer with the paired signal; CONNECTED → read the firmware (ack 28) and the battery
/// → Connected / DfuNeeded / BatteryNeeded. The pendant's identifier is saved once it
/// reaches CONNECTED and reconnected to from then on (also in the background).
final class HeartPendant: NSObject, ObservableObject {
    @Published private(set) var state: HeartState = .idle
    @Published private(set) var battery: Int?
    @Published private(set) var firmware: HeartFirmware?
    @Published private(set) var counts: HeartCounts?
    /// The last event or problem worth showing.
    @Published private(set) var lastEvent: String?
    @Published private(set) var savedID: UUID? {
        didSet { UserDefaults.standard.set(savedID?.uuidString, forKey: Self.savedKey) }
    }

    var isPaired: Bool { savedID != nil }

    private static let savedKey = "HeartPendantID"
    private static let auidKey = "HeartSavedAUID"
    private static let restoreID = "BondTouchBeyond.heart"

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var notifyChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    private var countChar: CBCharacteristic?
    private var batteryChar: CBCharacteristic?
    /// True while the user asked to pair (accept any "BondHeart", not just the saved one).
    private var pairing = false
    private var scanTimeout: DispatchWorkItem?
    private var gotState = false

    private var patternWait: CheckedContinuation<Void, Error>?
    private var countWait: CheckedContinuation<HeartCounts, Error>?
    private var patternToken = 0
    private var countToken = 0

    override init() {
        super.init()
        if let s = UserDefaults.standard.string(forKey: Self.savedKey), let id = UUID(uuidString: s) {
            savedID = id
            state = .searching
            // A pendant is paired: bring Bluetooth up now so it reconnects (and so iOS can
            // hand a restored connection back after relaunching the app).
            makeCentral()
        }
    }

    /// The app's id for this phone, sent as the AUID (persisted random u32, as the original).
    private var auid: UInt32 {
        if let v = UserDefaults.standard.object(forKey: Self.auidKey) as? Int { return UInt32(truncatingIfNeeded: v) }
        let v = UInt32.random(in: .min ... .max)
        UserDefaults.standard.set(Int(v), forKey: Self.auidKey)
        return v
    }

    private func makeCentral() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID,
                                             CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: - Public

    /// Called when the Bond Heart screen opens: starts Bluetooth and reconnects the saved
    /// pendant if there is one.
    func activate() {
        makeCentral()
        if let central, central.state == .poweredOn, isPaired, peripheral?.state != .connected {
            reconnectSaved()
            scan(timeout: 30)
        }
    }

    /// Looks for a pendant to pair (wake it: press both surfaces and tap until it flashes).
    func startPairing() {
        makeCentral()
        pairing = true
        lastEvent = nil
        guard let central, central.state == .poweredOn else { return }   // resumes in didUpdateState
        if let p = peripheral, p.state != .disconnected { central.cancelPeripheralConnection(p) }
        scan(timeout: 30)
    }

    /// Forgets the pendant. iOS keeps its Bluetooth bond: remove "BondHeart" in
    /// Settings → Bluetooth to fully unpair it (the original asks the same).
    func forget() {
        pairing = false
        stopScan()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        clearCharacteristics()
        savedID = nil
        UserDefaults.standard.removeObject(forKey: Self.auidKey)
        battery = nil; firmware = nil; counts = nil; lastEvent = nil
        state = .idle
    }

    /// Writes a heartbeat (inter-beat intervals in ms) to the pendant: it beats it when held.
    @MainActor
    func wear(intervals: [Int]) async throws {
        guard state.isUsable, let p = peripheral, let c = notifyChar else { throw HeartPendantError.notConnected }
        guard intervals.count >= 2 else { throw HeartPendantError.tooShort }
        let bytes = HeartGATT.pattern(intervals)
        NetLog.shared.record(.send, "Heart: wear pattern", bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
        guard c.properties.contains(.write) else {
            p.writeValue(Data(bytes), for: c, type: .withoutResponse)
            return
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            patternWait?.resume(throwing: HeartPendantError.timeout)
            patternWait = cont
            p.writeValue(Data(bytes), for: c, type: .withResponse)
            patternToken += 1
            let token = patternToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, self.patternToken == token, let wait = self.patternWait else { return }
                self.patternWait = nil
                wait.resume(throwing: HeartPendantError.timeout)
            }
        }
    }

    /// Reads the played / beats counters (the first read may make iOS ask to pair).
    @MainActor @discardableResult
    func readCounts() async throws -> HeartCounts {
        guard state.isUsable, let p = peripheral, let c = countChar else { throw HeartPendantError.notConnected }
        let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HeartCounts, Error>) in
            countWait?.resume(throwing: HeartPendantError.timeout)
            countWait = cont
            p.readValue(for: c)
            countToken += 1
            let token = countToken
            // Long enough for iOS's pairing prompt on the first (encrypted) read.
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                guard let self, self.countToken == token, let wait = self.countWait else { return }
                self.countWait = nil
                wait.resume(throwing: HeartPendantError.timeout)
            }
        }
        counts = result
        return result
    }

    /// Re-reads the battery level.
    func refreshBattery() {
        if let p = peripheral, let c = batteryChar { p.readValue(for: c) }
    }

    // MARK: - Internals

    private func scan(timeout: Double) {
        guard let central, central.state == .poweredOn else { return }
        if !state.isUsable, state != .oobe, state != .authenticating, state != .connecting { state = .searching }
        // The original filters by name; the pendant's advertised services aren't known, so
        // scan for everything and match the name.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.central?.stopScan()
            if self.state == .searching {
                self.lastEvent = "Uh-oh, your Heart fell asleep. Hold and double-tap it until it flashes, then search again."
                self.state = self.isPaired ? .searching : .idle
                self.pairing = false
            }
        }
        scanTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    private func stopScan() {
        scanTimeout?.cancel()
        scanTimeout = nil
        central?.stopScan()
    }

    /// A pending connect to the saved pendant: iOS completes it whenever it wakes, even with
    /// the app in the background.
    private func reconnectSaved() {
        guard let central, let id = savedID,
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        peripheral = p
        p.delegate = self
        if p.state == .disconnected { central.connect(p, options: nil) }
        if !state.isUsable { state = .searching }
    }

    private func connect(_ p: CBPeripheral) {
        stopScan()
        if let old = peripheral, old != p, old.state != .disconnected { central?.cancelPeripheralConnection(old) }
        peripheral = p
        p.delegate = self
        state = .connecting
        central?.connect(p, options: nil)
    }

    private func clearCharacteristics() {
        notifyChar = nil; commandChar = nil; countChar = nil; batteryChar = nil
        gotState = false
    }

    private func send(_ bytes: [UInt8]) {
        guard let p = peripheral, let c = commandChar else { return }
        let type: CBCharacteristicWriteType = c.properties.contains(.write) ? .withResponse : .withoutResponse
        p.writeValue(Data(bytes), for: c, type: type)
    }

    private func handle(notify data: Data) {
        let b = [UInt8](data)
        guard let kind = b.first else { return }
        switch kind {
        case 0x01:
            guard b.count > 1, let s = HeartPeripheralState(rawValue: b[1]) else { return }
            gotState = true
            NetLog.shared.record(.recv, "Heart: state \(s)")
            switch s {
            case .waitingToken:
                state = .authenticating
                send(HeartGATT.token)
                send(HeartGATT.auid(auid))
            case .waitingAuid:
                state = .authenticating
                send(HeartGATT.auid(auid))
            case .oobe:
                state = .oobe
            case .connected:
                if let p = peripheral { savedID = p.identifier }
                pairing = false
                if !state.isUsable { state = .authenticating }
                send(HeartGATT.readFirmware)
                refreshBattery()
            }
        case 0x02:
            guard b.count > 1, let e = HeartEvent(rawValue: b[1]) else { return }
            NetLog.shared.record(.recv, "Heart: event \(e)")
            if e == .pairedSignal {
                send(HeartGATT.pairedSignal)
            } else if e.rawValue < HeartEvent.factoryButtonPressed.rawValue {
                lastEvent = e.text
            }
        case 0x0A:
            guard b.count > 1 else { return }
            if b[1] == 28, b.count >= 6 {
                firmware = HeartFirmware(major: Int(b[2]), minor: Int(b[3]), patch: Int(b[4]), build: Int(b[5]))
                evaluate()
            }
        default:
            break
        }
    }

    /// Connected / DfuNeeded / BatteryNeeded, from the firmware and battery (as the original's
    /// onFirmwareVersion: older than 1.0.3.10 → DFU if the battery is at least 50 %).
    private func evaluate() {
        guard let fw = firmware else { return }
        if fw >= HeartGATT.currentFirmware { state = .connected }
        else if (battery ?? 0) >= 50 { state = .dfuNeeded }
        else { state = .needsBattery }
        if fw < HeartGATT.minimumFirmware {
            lastEvent = "This Heart's firmware (\(fw.text)) is older than the original app supports; update it with the Bond Touch app."
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension HeartPendant: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let p = peripheral, p.state == .connected {
                p.discoverServices([HeartGATT.service, HeartGATT.batteryService])
            } else if isPaired {
                reconnectSaved()
                if pairing { scan(timeout: 30) }
            } else if pairing {
                scan(timeout: 30)
            } else {
                state = .idle
            }
        case .poweredOff:
            state = .bluetoothOff
            clearCharacteristics()
        case .unauthorized:
            state = .unauthorized
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        if name?.uppercased() == HeartGATT.dfuName {
            if !state.isUsable { state = .dfuMode }
            return
        }
        guard HeartGATT.isPendantName(name) else { return }
        // Paired: only ours (unless the user is pairing a new one), as the original.
        if let saved = savedID, saved != peripheral.identifier, !pairing { return }
        if peripheral == self.peripheral, peripheral.state != .disconnected { return }
        NetLog.shared.record(.recv, "Heart: found \(name ?? "BondHeart")")
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let p = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first else { return }
        peripheral = p
        p.delegate = self
        state = p.state == .connected ? .connecting : .searching
        // Services are rediscovered in centralManagerDidUpdateState once powered on.
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        clearCharacteristics()
        state = .connecting
        peripheral.discoverServices([HeartGATT.service, HeartGATT.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lastEvent = error?.localizedDescription
        state = isPaired ? .searching : .idle
        if isPaired { reconnectSaved() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == self.peripheral else { return }
        clearCharacteristics()
        patternWait?.resume(throwing: HeartPendantError.notConnected); patternWait = nil
        countWait?.resume(throwing: HeartPendantError.notConnected); countWait = nil
        // The pendant sleeps a short while after it's put down; wait for it to wake again.
        if isPaired, peripheral.identifier == savedID {
            state = .searching
            central.connect(peripheral, options: nil)
        } else {
            state = pairing ? .searching : .idle
            if pairing { scan(timeout: 30) }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension HeartPendant: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            switch c.uuid {
            case HeartGATT.notify:
                notifyChar = c
                peripheral.setNotifyValue(true, for: c)
            case HeartGATT.command: commandChar = c
            case HeartGATT.count: countChar = c
            case HeartGATT.batteryLevel:
                batteryChar = c
                if c.properties.contains(.notify) { peripheral.setNotifyValue(true, for: c) }
                peripheral.readValue(for: c)
            default: break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == HeartGATT.notify, error == nil else {
            if let error, characteristic.uuid == HeartGATT.notify { lastEvent = error.localizedDescription }
            return
        }
        if !state.isUsable { state = .authenticating }
        // The pendant normally reports its state as soon as we subscribe. If it doesn't
        // (not observed — a guess), start the handshake ourselves.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.gotState, self.notifyChar != nil else { return }
            NetLog.shared.record(.send, "Heart: no state reported — sending token and AUID")
            self.send(HeartGATT.token)
            self.send(HeartGATT.auid(self.auid))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        switch characteristic.uuid {
        case HeartGATT.notify:
            if let v = characteristic.value { handle(notify: v) }
        case HeartGATT.batteryLevel:
            if let v = characteristic.value?.first {
                battery = Int(v)
                if state.isUsable { evaluate() }
            }
        case HeartGATT.count:
            if let error {
                countWait?.resume(throwing: HeartPendantError.failed(error.localizedDescription)); countWait = nil
                return
            }
            let b = [UInt8](characteristic.value ?? Data())
            func u32(_ at: Int) -> Int {
                guard b.count >= at + 4 else { return 0 }
                return Int(UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24)
            }
            guard b.count >= 4 else {
                countWait?.resume(throwing: HeartPendantError.failed("The Heart sent no count.")); countWait = nil
                return
            }
            countWait?.resume(returning: HeartCounts(played: u32(0), beats: u32(4))); countWait = nil
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { NetLog.shared.record(.fail, "Heart: write failed", error.localizedDescription) }
        guard characteristic.uuid == HeartGATT.notify else { return }
        if let error {
            patternWait?.resume(throwing: HeartPendantError.failed(error.localizedDescription))
        } else {
            patternWait?.resume()
        }
        patternWait = nil
    }
}
