import CoreBluetooth
import Foundation

/// Bond Touch bracelet GATT layout and wire format (v3 protocol), reverse-engineered
/// from the official app for interoperability. See `docs/BLE_PROTOCOL.md`.
///
/// The bracelet is a Nordic nRF device. Current hardware (BOND / Bond More / BOND 4 /
/// BOND MINI) speaks the v3 protocol implemented here.
enum BondGATT {
    /// Primary vendor service.
    static let service = CBUUID(string: "d3c00003-add3-1d4b-0000-0000b5006bb1")
    /// FFB1 — write: LED / motor / config / menu commands.
    static let ffb1 = CBUUID(string: "d3c0ffb1-add3-1d4b-0000-0000b5006bb1")
    /// FFB2 — write: touch rhythm; notify: incoming touches/events.
    static let ffb2 = CBUUID(string: "d3c0ffb2-add3-1d4b-0000-0000b5006bb1")
    /// Client Characteristic Configuration Descriptor (enable notifications).
    static let cccd = CBUUID(string: "00002902-0000-1000-8000-00805f9b34fb")
    static let batteryService = CBUUID(string: "0000180f-0000-1000-8000-00805f9b34fb")
    static let batteryLevel = CBUUID(string: "00002a19-0000-1000-8000-00805f9b34fb")

    static let touchWrite = ffb2   // touches go out on FFB2
    static let touchNotify = ffb2  // and arrive on FFB2 notifications

    /// Advertised name prefixes in normal (non-DFU) mode.
    static let deviceNames = ["BOND", "Bond More", "BOND 4", "BOND MINI"]
    static let dfuNames = ["BOND_DFU", "BOND_M_DFU", "BOND_4_DFU", "BOND_MINI_DFU"]

    static func isBondName(_ name: String?) -> Bool {
        guard let name else { return false }
        let upper = name.uppercased()
        // Matches BOND, BOND MORE, BOND 4, BOND MINI (and DFU variants) case-insensitively.
        return upper.hasPrefix("BOND")
    }

    /// The protocol is resolved (real UUIDs/format), so the manager can drive hardware.
    static let isResolved = true

    // MARK: - Outgoing frames

    /// FFB2 touch frame: the tap rhythm as bytes, padded with 0xFF to 20 bytes.
    static func encodeTouch(_ touch: TouchMessage) -> Data {
        var frame = [UInt8]()
        // Byte 0 marks a touch payload (matches the incoming 0x19 convention); the
        // remaining bytes are the per-tap values. A single tap is just [0x19].
        frame.append(0x19)
        for gap in touch.pattern {
            frame.append(UInt8(clamping: gap / 10)) // 10ms units, byte-sized
        }
        while frame.count < 20 { frame.append(0xFF) }
        return Data(frame.prefix(20))
    }

    /// FFB1 LED + motor command (opcode 0x26) — buzz + glow in the touch's colour.
    static func encodeLedAndMotor(colorRGB: Int,
                                  vibrationStrength: UInt8 = 200,
                                  vibrationMs: UInt16 = 400,
                                  brightness: UInt8 = 255,
                                  holdMs: UInt16 = 600) -> Data {
        let r = UInt8((colorRGB >> 16) & 0xFF)
        let g = UInt8((colorRGB >> 8) & 0xFF)
        let b = UInt8(colorRGB & 0xFF)
        var f = [UInt8]()
        f += [0x26, 0x00, vibrationStrength]          // opcode, queue, vib strength
        f += u16le(vibrationMs)                        // vibration time
        f += [0x01, r, g, b, brightness]               // ledMode=1, RGB, brightness
        f += u16le(80)                                 // led transition time
        f += u16le(holdMs)                             // led hold time
        f += u16le(80)                                 // led sleep time
        f += u16le(holdMs)                             // led execute time
        while f.count < 20 { f.append(0x00) }
        return Data(f.prefix(20))
    }

    /// A single heartbeat pulse: a short, firm buzz with a brief glow. Sent once per beat
    /// by the heartbeat player to make the bracelet feel like a pulse.
    static func encodeHeartbeatPulse(colorRGB: Int) -> Data {
        encodeLedAndMotor(colorRGB: colorRGB, vibrationStrength: 220, vibrationMs: 130,
                          brightness: 255, holdMs: 130)
    }

    // MARK: - Incoming

    /// Parses an FFB2 notification into a received touch rhythm, or nil if it's not a
    /// touch frame (0x19, length >= 14 per the app).
    static func decodeTap(_ data: Data) -> [Int]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 14, bytes[0] == 0x19 else { return nil }
        return bytes.dropFirst()
            .prefix { $0 != 0xFF }
            .map { Int($0) * 10 }  // back to milliseconds
    }

    private static func u16le(_ x: UInt16) -> [UInt8] { [UInt8(x & 0xFF), UInt8((x >> 8) & 0xFF)] }
}
