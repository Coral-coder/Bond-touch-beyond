import CoreBluetooth
import Foundation

enum BraceletState: Equatable {
    case bluetoothOff
    case scanning
    case connecting
    case connected
    case disconnected
}

/// CoreBluetooth central that talks to a Bond Touch bracelet using the reverse-engineered
/// v3 protocol in `BondGATT`. Scans for the vendor service, connects, enables FFB2
/// notifications, and sends touches (FFB2) plus buzz/glow (FFB1). Writes are serialised:
/// the next write waits for the previous write's response, which the bracelet requires.
final class BraceletManager: NSObject, ObservableObject {
    @Published private(set) var state: BraceletState = .disconnected
    /// Delivered when the wearer taps their own bracelet (to relay to the partner).
    var onLocalTap: (([Int]) -> Void)?

    private var central: CBCentralManager!
    private var bracelet: CBPeripheral?
    private var ffb1: CBCharacteristic?   // LED / motor
    private var ffb2: CBCharacteristic?   // touch write + notify

    private var writeQueue: [Data] = []
    private var writing = false

    private var heartbeatTimer: Timer?
    private var heartbeatWatchdog: Timer?
    private var heartbeatBPM = 0
    /// True while the partner's heartbeat is beating on this bracelet.
    @Published private(set) var heartbeatActive = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard central.state == .poweredOn else { state = .bluetoothOff; return }
        state = .scanning
        central.scanForPeripherals(withServices: [BondGATT.service])
    }

    /// Plays a touch: send the rhythm on FFB2 and a matching buzz/glow on FFB1.
    func play(_ touch: TouchMessage) {
        enqueue(BondGATT.encodeTouch(touch), to: ffb2)
        enqueue(BondGATT.encodeLedAndMotor(colorRGB: touch.colorRGB), to: ffb1)
    }

    // MARK: - Heartbeat playback

    /// Beats the bracelet at the given BPM (one firm pulse per beat) until `stopHeartbeat()`
    /// or ~15s pass with no refresh. Call again with a new BPM to retune live.
    func startHeartbeat(bpm: Int, colorRGB: Int = 0xF44336) {
        let clamped = min(max(bpm, 30), 220)
        resetHeartbeatWatchdog()
        guard clamped != heartbeatBPM || heartbeatTimer == nil else { return }
        heartbeatBPM = clamped
        heartbeatTimer?.invalidate()
        heartbeatActive = true
        let interval = 60.0 / Double(clamped)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, let bracelet = self.bracelet, let ffb1 = self.ffb1 else { return }
            self.writeQueue.append(BondGATT.encodeHeartbeatPulse(colorRGB: colorRGB))
            self.pumpQueue(characteristic: ffb1, peripheral: bracelet)
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    func stopHeartbeat() {
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        heartbeatWatchdog?.invalidate(); heartbeatWatchdog = nil
        heartbeatBPM = 0
        heartbeatActive = false
    }

    private func resetHeartbeatWatchdog() {
        heartbeatWatchdog?.invalidate()
        let w = Timer(timeInterval: 15, repeats: false) { [weak self] _ in self?.stopHeartbeat() }
        RunLoop.main.add(w, forMode: .common)
        heartbeatWatchdog = w
    }

    private func enqueue(_ data: Data, to characteristic: CBCharacteristic?) {
        guard let characteristic, let bracelet else { return }
        writeQueue.append(data)
        pumpQueue(characteristic: characteristic, peripheral: bracelet)
    }

    private func pumpQueue(characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        guard !writing, !writeQueue.isEmpty else { return }
        writing = true
        let next = writeQueue.removeFirst()
        peripheral.writeValue(next, for: characteristic, type: .withResponse)
    }
}

extension BraceletManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if state == .disconnected || state == .bluetoothOff { startScanning() }
        case .poweredOff: state = .bluetoothOff
        default: state = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard BondGATT.isBondName(advName) else { return }
        bracelet = peripheral
        peripheral.delegate = self
        state = .connecting
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BondGATT.service])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        state = .disconnected
        ffb1 = nil; ffb2 = nil
        writeQueue.removeAll(); writing = false
    }
}

extension BraceletManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == BondGATT.service }) else { return }
        peripheral.discoverCharacteristics([BondGATT.ffb1, BondGATT.ffb2], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == BondGATT.ffb1 { ffb1 = char }
            if char.uuid == BondGATT.ffb2 {
                ffb2 = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
        state = .connected
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        writing = false
        // Continue draining whichever characteristic still has queued writes.
        if let next = ffb2 ?? ffb1 { pumpQueue(characteristic: next, peripheral: peripheral) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == BondGATT.ffb2,
              let data = characteristic.value,
              let pattern = BondGATT.decodeTap(data) else { return }
        onLocalTap?(pattern)
    }
}
