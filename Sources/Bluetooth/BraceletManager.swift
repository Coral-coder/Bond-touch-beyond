import CoreBluetooth
import Foundation

enum BraceletState: Equatable {
    case bluetoothOff
    case unsupportedUntilProtocolResolved
    case scanning
    case connecting
    case connected
    case disconnected
}

/// CoreBluetooth central that talks to the bracelet. The actual commands it sends
/// come from `BondGATT`; until that's resolved this manager stays in
/// `.unsupportedUntilProtocolResolved` and never fabricates a connection.
final class BraceletManager: NSObject, ObservableObject {
    @Published private(set) var state: BraceletState = .disconnected
    /// Delivered when the wearer taps their own bracelet (to relay to the partner).
    var onLocalTap: (([Int]) -> Void)?

    private var central: CBCentralManager!
    private var bracelet: CBPeripheral?
    private var writeChar: CBCharacteristic?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard BondGATT.isResolved, let service = BondGATT.service else {
            state = .unsupportedUntilProtocolResolved
            return
        }
        guard central.state == .poweredOn else { state = .bluetoothOff; return }
        state = .scanning
        central.scanForPeripherals(withServices: [service])
    }

    /// Plays a touch on the connected bracelet.
    func play(_ touch: TouchMessage) throws {
        guard let bracelet, let writeChar else { throw BondGATTError.protocolNotResolved }
        let frame = try BondGATT.encode(touch)
        bracelet.writeValue(frame, for: writeChar, type: .withResponse)
    }
}

extension BraceletManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if BondGATT.isResolved { /* ready; UI triggers scan */ }
            else { state = .unsupportedUntilProtocolResolved }
        case .poweredOff:
            state = .bluetoothOff
        default:
            state = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Optional extra filter on advertised name once we know the prefix.
        if let prefix = BondGATT.advertisedNamePrefix,
           let name = peripheral.name, !name.hasPrefix(prefix) { return }
        bracelet = peripheral
        peripheral.delegate = self
        state = .connecting
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let service = BondGATT.service { peripheral.discoverServices([service]) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        state = .disconnected
    }
}

extension BraceletManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first else { return }
        var chars: [CBUUID] = []
        if let w = BondGATT.touchWrite { chars.append(w) }
        if let n = BondGATT.touchNotify { chars.append(n) }
        peripheral.discoverCharacteristics(chars.isEmpty ? nil : chars, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == BondGATT.touchWrite { writeChar = char }
            if char.uuid == BondGATT.touchNotify { peripheral.setNotifyValue(true, for: char) }
        }
        state = .connected
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == BondGATT.touchNotify,
              let data = characteristic.value,
              let pattern = try? BondGATT.decodeTap(data) else { return }
        onLocalTap?(pattern)
    }
}
