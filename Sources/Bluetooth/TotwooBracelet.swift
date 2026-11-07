import CoreBluetooth
import Foundation

/// CoreBluetooth central for totwoo jewellery, alongside the Bond Touch bracelet
/// (`BraceletManager`) and the Bond Heart pendant, with its own restore identifier.
///
/// Flow, as the totwoo app: connect → subscribe to battery, the raw stream and the vendor
/// notify channels → read model / hardware / serial / firmware → set the time → ready.
/// A partner's touch lights it in their colour (the "totwoo" notify event); a tap on the
/// jewellery (an unsolicited event from it) can send a touch back. What each mode byte does
/// isn't documented, so they're adjustable on the totwoo screen, and every frame the jewellery
/// sends is written to the network log, so new events can be read off it.
final class TotwooBracelet: NSObject, ObservableObject {
    enum State: Equatable {
        case bluetoothOff, unauthorized, idle, searching, connecting, connected

        var text: String {
            switch self {
            case .bluetoothOff: return "Bluetooth is off"
            case .unauthorized: return "Bluetooth access is off for this app"
            case .idle: return "Not paired"
            case .searching: return "Looking for your totwoo…"
            case .connecting: return "Connecting…"
            case .connected: return "Connected"
            }
        }
    }

    /// A nearby device while pairing.
    struct Found: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
        let likely: Bool
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var battery: Int?
    @Published private(set) var model: String?
    @Published private(set) var firmware: String?
    @Published private(set) var serial: String?
    @Published private(set) var lastEvent: String?
    /// Devices seen while pairing, the likely totwoo ones first.
    @Published private(set) var found: [Found] = []
    @Published private(set) var savedID: UUID? {
        didSet { UserDefaults.standard.set(savedID?.uuidString, forKey: Self.savedKey) }
    }

    /// The two mode bytes of the notify event (what kind of alert, which flash style).
    @Published var notifyMode: Int = UserDefaults.standard.object(forKey: "totwooMode") as? Int ?? 1 {
        didSet { UserDefaults.standard.set(notifyMode, forKey: "totwooMode") }
    }
    @Published var notifyStyle: Int = UserDefaults.standard.object(forKey: "totwooStyle") as? Int ?? 1 {
        didSet { UserDefaults.standard.set(notifyStyle, forKey: "totwooStyle") }
    }
    /// Also vibrate with this pattern on a partner's touch (0 = don't).
    @Published var vibration: Int = UserDefaults.standard.object(forKey: "totwooVibration") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(vibration, forKey: "totwooVibration") }
    }
    /// A tap on the jewellery sends the selected partner a touch.
    @Published var tapSends: Bool = UserDefaults.standard.object(forKey: "totwooTapSends") as? Bool ?? true {
        didSet { UserDefaults.standard.set(tapSends, forKey: "totwooTapSends") }
    }

    /// Called on main when the wearer taps the jewellery.
    var onTap: (() -> Void)?

    var isPaired: Bool { savedID != nil }
    var isReady: Bool { state == .connected && writeChar != nil }

    private static let savedKey = "TotwooID"
    private static let restoreID = "BondTouchBeyond.totwoo"

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var batteryChar: CBCharacteristic?
    private var reader = TotwooProtocol.Reader()
    private var nextIndex: UInt16 = 1
    private var pairing = false
    private var scanTimeout: DispatchWorkItem?
    private var lastTap = Date.distantPast

    override init() {
        super.init()
        if let s = UserDefaults.standard.string(forKey: Self.savedKey), let id = UUID(uuidString: s) {
            savedID = id
            state = .searching
            makeCentral()
        }
    }

    private func makeCentral() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID,
                                             CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: - Public

    /// Called when the totwoo screen opens: Bluetooth on, saved jewellery reconnected.
    func activate() {
        makeCentral()
        if let central, central.state == .poweredOn, isPaired, peripheral?.state != .connected { reconnectSaved() }
    }

    /// Lists nearby devices so the user can pick their totwoo.
    func startPairing() {
        makeCentral()
        pairing = true
        found = []
        lastEvent = nil
        guard let central, central.state == .poweredOn else { return }
        scan(timeout: 25)
    }

    func pair(_ id: UUID) {
        guard let p = central?.retrievePeripherals(withIdentifiers: [id]).first else { return }
        pairing = false
        stopScan()
        savedID = id
        connect(p)
    }

    func forget() {
        pairing = false
        stopScan()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        writeChar = nil; batteryChar = nil
        savedID = nil
        battery = nil; model = nil; firmware = nil; serial = nil; lastEvent = nil
        state = .idle
    }

    /// A partner's touch: the jewellery lights in its colour (and vibrates, if set).
    func play(_ touch: TouchMessage) {
        guard isReady else { return }
        notify(rgb: touch.colorRGB)
        if vibration > 0 { send(TotwooProtocol.vibrate(pattern: UInt8(clamping: vibration))) }
    }

    func notify(rgb: Int) {
        send(TotwooProtocol.notify(rgb: rgb, mode: UInt8(clamping: notifyMode), style: UInt8(clamping: notifyStyle)))
    }

    func vibrate(pattern: Int) {
        send(TotwooProtocol.vibrate(pattern: UInt8(clamping: pattern)))
    }

    func setTouchColor(_ rgb: Int) {
        send(TotwooProtocol.setTouchColor(rgb))
    }

    // MARK: - Internals

    private func send(_ command: (UInt8, [TotwooProtocol.Segment])) {
        guard let p = peripheral, let c = writeChar else { return }
        let packet = TotwooProtocol.Packet(index: nextIndex, command: command.0, segments: command.1)
        nextIndex = nextIndex == .max ? 1 : nextIndex + 1
        let type: CBCharacteristicWriteType = c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        for frame in TotwooProtocol.frames(packet) {
            p.writeValue(Data(frame), for: c, type: type)
        }
        NetLog.shared.record(.send, "totwoo: cmd \(String(format: "%02x", command.0))",
                             TotwooProtocol.frames(packet).map(TotwooProtocol.hex).joined(separator: " | "))
    }

    private func scan(timeout: Double) {
        guard let central, central.state == .poweredOn else { return }
        if state != .connected { state = .searching }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.central?.stopScan()
            if self.state == .searching, !self.isPaired { self.state = .idle }
            if self.pairing, self.found.isEmpty {
                self.lastEvent = "No totwoo found. Wake it (tap it so it lights up), keep it close and try again."
            }
            self.pairing = false
        }
        scanTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    private func stopScan() {
        scanTimeout?.cancel()
        scanTimeout = nil
        central?.stopScan()
    }

    private func reconnectSaved() {
        guard let central, let id = savedID,
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        peripheral = p
        p.delegate = self
        if p.state == .disconnected { central.connect(p, options: nil) }
        if state != .connected { state = .searching }
    }

    private func connect(_ p: CBPeripheral) {
        if let old = peripheral, old != p, old.state != .disconnected { central?.cancelPeripheralConnection(old) }
        peripheral = p
        p.delegate = self
        state = .connecting
        central?.connect(p, options: nil)
    }

    private func handle(frame bytes: [UInt8]) {
        NetLog.shared.record(.recv, "totwoo: frame", TotwooProtocol.hex(bytes))
        guard let first = bytes.first else { return }
        // Bulk uploads: acknowledge each block so the jewellery moves on.
        if first == 0xC1 || first == 0xC3, bytes.count >= 3 {
            send(TotwooProtocol.ack(type: first == 0xC1 ? 0x01 : 0x03, counter: [bytes[1], bytes[2]]))
            return
        }
        guard let packet = reader.feed(bytes) else { return }
        let segs = packet.segments.map { "type \(String(format: "%02x", $0.type)): \(TotwooProtocol.hex($0.value))" }.joined(separator: "; ")
        NetLog.shared.record(.recv, "totwoo: cmd \(String(format: "%02x", packet.command))\(packet.isReply ? " (reply)" : "")", segs)
        // An event the jewellery raised itself (not a reply to us, not an acknowledgement):
        // the wearer touched it.
        if !packet.isReply, packet.command == 0x02 || packet.command == 0x05 {
            lastEvent = "Tapped \(Date().formatted(date: .omitted, time: .shortened))"
            if tapSends, Date().timeIntervalSince(lastTap) > 2 {
                lastTap = Date()
                onTap?()
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension TotwooBracelet: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let p = peripheral, p.state == .connected {
                p.discoverServices(nil)
            } else if isPaired {
                reconnectSaved()
            } else if pairing {
                scan(timeout: 25)
            } else {
                state = .idle
            }
        case .poweredOff:
            state = .bluetoothOff
            writeChar = nil
        case .unauthorized:
            state = .unauthorized
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard pairing else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard let name, !name.isEmpty else { return }
        let likely = TotwooGATT.looksLikeTotwoo(name: name, services: services)
        let item = Found(id: peripheral.identifier, name: name, rssi: RSSI.intValue, likely: likely)
        if let i = found.firstIndex(where: { $0.id == item.id }) { found[i] = item } else { found.append(item) }
        found.sort { ($0.likely ? 1 : 0, $0.rssi) > ($1.likely ? 1 : 0, $1.rssi) }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let p = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first else { return }
        peripheral = p
        p.delegate = self
        state = p.state == .connected ? .connecting : .searching
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        writeChar = nil
        reader = TotwooProtocol.Reader()
        state = .connecting
        NetLog.shared.record(.ok, "totwoo: connected", peripheral.name ?? "")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lastEvent = error?.localizedDescription
        state = isPaired ? .searching : .idle
        if isPaired { reconnectSaved() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == self.peripheral else { return }
        writeChar = nil
        if isPaired, peripheral.identifier == savedID {
            state = .searching
            central.connect(peripheral, options: nil)   // completes whenever it's back in range
        } else {
            state = .idle
        }
    }
}

// MARK: - CBPeripheralDelegate

extension TotwooBracelet: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            switch c.uuid {
            case TotwooGATT.write:
                writeChar = c
                // Set the time once the primary channel is there, then it's ready (§3).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.writeChar != nil else { return }
                    self.send(TotwooProtocol.setTime())
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        guard let self, self.writeChar != nil else { return }
                        self.state = .connected
                    }
                }
            case TotwooGATT.notify, TotwooGATT.notify2, TotwooGATT.notify3, TotwooGATT.stream:
                peripheral.setNotifyValue(true, for: c)
            case TotwooGATT.batteryLevel:
                batteryChar = c
                if c.properties.contains(.notify) { peripheral.setNotifyValue(true, for: c) }
                peripheral.readValue(for: c)
            case TotwooGATT.modelNumber, TotwooGATT.serialNumber, TotwooGATT.softwareRevision:
                peripheral.readValue(for: c)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        let text = String(data: value, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters.union(.whitespaces))
        switch characteristic.uuid {
        case TotwooGATT.batteryLevel: battery = value.first.map(Int.init)
        case TotwooGATT.modelNumber: model = text
        case TotwooGATT.serialNumber: serial = text
        case TotwooGATT.softwareRevision: firmware = text
        case TotwooGATT.notify, TotwooGATT.notify2, TotwooGATT.notify3:
            handle(frame: [UInt8](value))
        case TotwooGATT.stream:
            NetLog.shared.record(.recv, "totwoo: stream", TotwooProtocol.hex([UInt8](value)))
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { NetLog.shared.record(.fail, "totwoo: write failed", error.localizedDescription) }
    }
}
