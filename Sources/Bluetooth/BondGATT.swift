import CoreBluetooth

/// The bracelet's GATT layout and wire format.
///
/// ⚠️ UNKNOWN UNTIL REVERSE-ENGINEERED. These values are NOT yet known. They must
/// come from one of:
///   • a BLE sniff of the official app talking to a real bracelet
///     (Android `btsnoop_hci.log`, or an nRF Connect / Wireshark capture), or
///   • static analysis of the official APK on a machine without the sandbox guard.
///
/// They are left as `nil`/placeholders ON PURPOSE. `BraceletManager` checks for this
/// and refuses to pretend it can drive the hardware until they're filled in, rather
/// than shipping made-up UUIDs that would silently never match a real device.
enum BondGATT {
    /// Vendor service advertised by the bracelet. UNKNOWN — fill from a capture.
    static let service: CBUUID? = nil

    /// Characteristic the app WRITES touch commands to. UNKNOWN — fill from a capture.
    static let touchWrite: CBUUID? = nil

    /// Characteristic the app subscribes to for button/tap events. UNKNOWN.
    static let touchNotify: CBUUID? = nil

    /// Local name prefix the bracelet advertises, used to filter scan results.
    /// UNKNOWN — a capture / the APK's scan filter will reveal the real prefix.
    static let advertisedNamePrefix: String? = nil

    /// True once someone has filled in the real protocol above.
    static var isResolved: Bool {
        service != nil && touchWrite != nil && touchNotify != nil
    }

    /// Encodes a touch into the bytes the bracelet expects on `touchWrite`.
    ///
    /// The real frame format (opcode, length, how the rhythm and colour are packed,
    /// any checksum) is part of what the capture/APK reveals. Until then this throws
    /// so callers can't accidentally send garbage to a device.
    static func encode(_ touch: TouchMessage) throws -> Data {
        throw BondGATTError.protocolNotResolved
    }

    /// Decodes an incoming notification (e.g. the wearer tapped their bracelet).
    static func decodeTap(_ data: Data) throws -> [Int] {
        throw BondGATTError.protocolNotResolved
    }
}

enum BondGATTError: Error {
    case protocolNotResolved
}
