import CoreBluetooth
import Foundation

/// Bond Touch bracelet generations. The original app supports five, selected at runtime
/// from the advertised service / API-version byte. See `docs/BLE_PROTOCOL.md`.
enum BondGeneration {
    case v1      // classic "BOND" (legacy FF06 protocol)
    case v2      // "BOND" / "Bond More" (API 0x42)
    case v4      // "BOND 4" (API 0x44)
    case mini    // "BOND MINI" (API 0x45)
    case v3      // "BTM" — devices exposing the d3c00003 service

    /// v4 and mini share the v2 app service / characteristics and frame format.
    var usesV2Base: Bool { self == .v2 || self == .v4 || self == .mini }
}

/// A decoded state signal from the bracelet's state/event channel.
enum BondSignal {
    case waitingToken
    case waitingAuid
    case connected
    case other
}

/// Bond Touch bracelet GATT layout and wire format, reverse-engineered from the official
/// app for interoperability. Vendor UUID base `d3c0XXXX-add3-1d4b-NODE-0000b5006bb1`
/// (NODE is `0000` except the app-service characteristics, which use `0001`).
enum BondGATT {
    // MARK: Services
    static let serviceV3  = CBUUID(string: "d3c00003-add3-1d4b-0000-0000b5006bb1")
    static let serviceOTA = CBUUID(string: "d3c00001-add3-1d4b-0000-0000b5006bb1")
    static let serviceApp = CBUUID(string: "d3c00002-add3-1d4b-0001-0000b5006bb1")
    static let batteryService = CBUUID(string: "0000180f-0000-1000-8000-00805f9b34fb")
    static let batteryLevel   = CBUUID(string: "00002a19-0000-1000-8000-00805f9b34fb")
    static let disService     = CBUUID(string: "0000180a-0000-1000-8000-00805f9b34fb")
    static let firmwareChar   = CBUUID(string: "00002a26-0000-1000-8000-00805f9b34fb")
    static let cccd           = CBUUID(string: "00002902-0000-1000-8000-00805f9b34fb")

    // MARK: v2 / v4 / mini characteristics (app service, node 0001)
    static let charToken   = CBUUID(string: "d3c0ffa1-add3-1d4b-0001-0000b5006bb1") // token write
    static let charAuid    = CBUUID(string: "d3c0ffa2-add3-1d4b-0001-0000b5006bb1") // AUID write
    static let charState   = CBUUID(string: "d3c0ffa4-add3-1d4b-0001-0000b5006bb1") // state notify
    static let charEvent   = CBUUID(string: "d3c0ffa5-add3-1d4b-0001-0000b5006bb1") // touch/event notify + write
    static let charAppCmd  = CBUUID(string: "d3c0ffa6-add3-1d4b-0001-0000b5006bb1") // app command write
    static let charApiVer  = CBUUID(string: "d3c0ffb3-add3-1d4b-0000-0000b5006bb1") // API-version read

    // MARK: v3 characteristics (service d3c00003, node 0000)
    static let v3ApiVer = CBUUID(string: "d3c0ff10-add3-1d4b-0000-0000b5006bb1")
    static let ffb1     = CBUUID(string: "d3c0ffb1-add3-1d4b-0000-0000b5006bb1") // app cmds + notify
    static let ffb2     = CBUUID(string: "d3c0ffb2-add3-1d4b-0000-0000b5006bb1") // touch pattern write

    // MARK: v1 characteristics
    static let v1Cmd   = CBUUID(string: "d3c0ff06-add3-1d4b-0000-0000b5006bb1")
    static let v1State = CBUUID(string: "d3c0ffa2-add3-1d4b-0001-0000b5006bb1")

    /// Fixed app-layer pairing token used by the shipping firmware.
    static let token: [UInt8] = Array("12345678".utf8)

    // MARK: Names
    static let deviceNames = ["BOND", "Bond More", "BOND 4", "BOND MINI"]
    static let dfuNames = ["BOND_DFU", "BOND_M_DFU", "BOND_4_DFU", "BOND_MINI_DFU"]

    static func isBondName(_ name: String?) -> Bool {
        guard let name else { return false }
        return name.uppercased().hasPrefix("BOND")
    }

    /// Generation from the API-version byte (non-v3) or the presence of the v3 service.
    static func generation(hasV3Service: Bool, apiVersion: UInt8?) -> BondGeneration {
        if hasV3Service { return .v3 }
        switch apiVersion {
        case 0x42: return .v2
        case 0x44: return .v4
        case 0x45: return .mini
        default:   return .v1
        }
    }

    /// Services to discover (nil → discover all, so we can detect the generation).
    static let discoverServices: [CBUUID]? = nil

    // MARK: - Pairing handshake

    /// Token write(s) for a generation: ASCII "12345678".
    static func tokenWrites(_ gen: BondGeneration) -> [(CBUUID, Data)] {
        switch gen {
        case .v3:
            return [(ffb1, pad(pfx(3) + token, to: 20))]
        case .v1:
            return [(charToken, Data(token))]
        default:
            return [(charToken, Data(token))]
        }
    }

    /// AUID write(s): the persisted per-install device/user id, little-endian u32.
    static func auidWrites(_ gen: BondGeneration, auid: UInt32) -> [(CBUUID, Data)] {
        switch gen {
        case .v3:
            return [(ffb1, pad(pfx(7) + u32le(auid), to: 20))]
        default:
            return [(charAuid, Data(u32le(auid)))]
        }
    }

    // MARK: - LED + motor (notification buzz + glow)

    /// A buzz + glow in `rgb`. v2-base uses the 0x26 LED+motor frame on the app-command
    /// characteristic; v3 uses the FFB1 colour + vibration commands.
    static func ledMotor(_ gen: BondGeneration, rgb: Int,
                         strength: UInt8 = 88, vibMs: UInt16 = 400,
                         brightness: UInt8 = 255, holdMs: UInt16 = 600) -> [(CBUUID, Data)] {
        let (r, g, b) = rgbBytes(rgb)
        switch gen {
        case .v3:
            let color = pfx(1) + [0x4B, 0x00, 0x00, r, g, b]
            let vib   = pfx(1) + [0x48, 0x00, vibLevel(strength), 0x00, 0x03]
            return [(ffb1, pad(color, to: 20)), (ffb1, pad(vib, to: 20))]
        case .v1:
            // FF06 ColorCommand (0x21) then LgtVibCommand (0x26).
            let color = u16le(0x21) + u16le(0) + u32le(UInt32(rgb & 0xFFFFFF)) + [100]
            let vib   = u16le(0x26) + u16le(0) + [0x00, 0x01, 0x01, 0x01]
            return [(v1Cmd, pad(color, to: 16)), (v1Cmd, pad(vib, to: 16))]
        default:
            var f: [UInt8] = [0x26, 0x00, 0x00, strength]
            f += u16le(vibMs)
            f += [0x01, r, g, b, brightness]
            f += u16le(80)      // transition
            f += u16le(holdMs)  // hold
            f += u16le(80)      // sleep
            f += u16le(holdMs)  // execute
            return [(charAppCmd, pad(f, to: 20))]
        }
    }

    /// One heartbeat pulse: a short firm buzz + glow.
    static func heartbeatPulse(_ gen: BondGeneration, rgb: Int) -> [(CBUUID, Data)] {
        ledMotor(gen, rgb: rgb, strength: 100, vibMs: 130, brightness: 255, holdMs: 130)
    }

    // MARK: - Sending a touch (replay the tap rhythm)

    /// Replays an on/off millisecond pattern as a touch in `rgb`.
    /// v2-base: a queue-pause marker, one 0x33 "send-message" step per on-segment, then a
    /// resume marker. v3: a single FFB2 frame carrying the duration bytes.
    static func touchSend(_ gen: BondGeneration, pattern: [Int],
                          startRGB: Int, endRGB: Int) -> [(CBUUID, Data)] {
        let onOff = pattern.isEmpty ? [200] : pattern
        switch gen {
        case .v3:
            return v3TouchFrames(onOff: onOff, startRGB: startRGB, endRGB: endRGB)
        case .v1:
            // v1 has no segmented send; fall back to a colour + buzz.
            return ledMotor(.v1, rgb: startRGB)
        default:
            var out: [(CBUUID, Data)] = [(charAppCmd, pad([0x32, 0x00, 0x22], to: 20))]
            let (r, g, b) = rgbBytes(startRGB)
            // Alternate on/off: even indices are "on" (buzz) segments. The 0x33 frame carries
            // the start→end gradient in its three colour slots.
            for (i, ms) in onOff.enumerated() where i % 2 == 0 {
                var f: [UInt8] = [0x33, 0x00, r, g, b]
                f += be3(startRGB) + be3(endRGB) + be3(endRGB)
                f += u16le(UInt16(clamping: ms))
                out.append((charAppCmd, pad(f, to: 20)))
            }
            out.append((charAppCmd, pad([0x32, 0x00, 0x11], to: 20)))
            return out
        }
    }

    private static func v3TouchFrames(onOff: [Int], startRGB: Int, endRGB: Int) -> [(CBUUID, Data)] {
        // Duration bytes (10 ms units, clamped to a byte), chunked 20 per packet.
        let durations = onOff.map { UInt8(clamping: $0 / 10) }
        let header: [UInt8] = [0x01, UInt8(clamping: durations.count), 0x01] + be3(startRGB) + be3(endRGB) + [0xFF]
        var frames: [(CBUUID, Data)] = [(ffb2, pad(header, to: 20))]
        var idx = 0
        while idx < durations.count {
            let chunk = Array(durations[idx..<min(idx + 20, durations.count)])
            frames.append((ffb2, pad(chunk, to: 20)))
            idx += 20
        }
        return frames
    }

    // MARK: - Incoming

    /// Interprets a state/event notification into a pairing signal.
    static func signal(_ gen: BondGeneration, uuid: CBUUID, data: Data) -> BondSignal {
        let b = [UInt8](data)
        guard !b.isEmpty else { return .other }
        if gen == .v3 && uuid == ffb1 {
            // category 0x04 = system events; byte1 is the bond-state id.
            guard b[0] == 0x04, b.count >= 2 else { return .other }
            switch b[1] {
            case 130: return .waitingToken
            case 131: return .waitingAuid
            case 133: return .connected
            default:  return .other
            }
        }
        if gen.usesV2Base && uuid == charState {
            switch b[0] {
            case 0x82: return .waitingToken
            case 0x83: return .waitingAuid
            case 0x85: return .connected
            default:   return .other
            }
        }
        return .other
    }

    /// A single parsed touch/tap event from the event characteristic.
    enum TouchEvent {
        case segment(touchMs: Int, releaseMs: Int, counter: Int, stop: Bool)
        case tap
        case doubleTap
        case ignored
    }

    /// Parses a v2-base AppEvent frame on the event characteristic (d3c0ffa5).
    static func touchEvent(_ gen: BondGeneration, uuid: CBUUID, data: Data) -> TouchEvent {
        guard gen.usesV2Base, uuid == charEvent else { return .ignored }
        let b = [UInt8](data)
        // A 0x19 blob of length >= 14 is a BLE-params payload, not a touch.
        if let first = b.first, first == 0x19, b.count >= 14 { return .ignored }
        guard b.count >= 14 else { return .ignored }
        let eventId = b[0]
        let counter = Int(b[1])
        let touchMs = Int(u32leAt(b, 2))
        let releaseMs = Int(u32leAt(b, 6))
        let stop = u32leAt(b, 10) == 0xFFFF_FFFF
        switch eventId {
        case 0x14: return .segment(touchMs: touchMs, releaseMs: releaseMs, counter: counter, stop: stop)
        case 0x16: return .tap
        case 0x17: return .doubleTap
        default:   return .ignored
        }
    }

    // MARK: - Byte helpers
    private static func pfx(_ p: UInt8) -> [UInt8] { [p] }
    static func u16le(_ x: UInt16) -> [UInt8] { [UInt8(x & 0xFF), UInt8((x >> 8) & 0xFF)] }
    static func u32le(_ x: UInt32) -> [UInt8] {
        [UInt8(x & 0xFF), UInt8((x >> 8) & 0xFF), UInt8((x >> 16) & 0xFF), UInt8((x >> 24) & 0xFF)]
    }
    static func be3(_ rgb: Int) -> [UInt8] {
        [UInt8((rgb >> 16) & 0xFF), UInt8((rgb >> 8) & 0xFF), UInt8(rgb & 0xFF)]
    }
    static func rgbBytes(_ rgb: Int) -> (UInt8, UInt8, UInt8) {
        (UInt8((rgb >> 16) & 0xFF), UInt8((rgb >> 8) & 0xFF), UInt8(rgb & 0xFF))
    }
    private static func u32leAt(_ b: [UInt8], _ i: Int) -> UInt32 {
        guard b.count >= i + 4 else { return 0 }
        return UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }
    /// Maps a 0–255 motor strength to the v3 vibration level 0–4.
    private static func vibLevel(_ strength: UInt8) -> UInt8 {
        UInt8(min(4, Int(strength) * 5 / 256))
    }
    private static func pad(_ bytes: [UInt8], to n: Int) -> Data {
        var f = bytes
        if f.count < n { f += Array(repeating: 0xFF, count: n - f.count) }
        return Data(f.prefix(n))
    }
}
