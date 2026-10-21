import CoreBluetooth
import Foundation

/// Bond Touch bracelet generations. The original app supports five, selected at runtime
/// from the advertised service / API-version byte. See `docs/BLE_PROTOCOL.md`.
enum BondGeneration {
    case v1      // classic "BOND" (legacy sequenced FF06-style frames on d3c0ffa6)
    case v2      // "BOND" / "Bond More" (API 0x42)
    case v4      // "BOND 4" (API 0x44)
    case mini    // "BOND MINI" (API 0x45)
    case v3      // "BTM" — devices exposing the d3c00003 service

    /// v4 and mini share the v2 app service / characteristics and frame format.
    var usesV2Base: Bool { self == .v2 || self == .v4 || self == .mini }
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
    static let modelChar      = CBUUID(string: "00002a24-0000-1000-8000-00805f9b34fb")
    static let cccd           = CBUUID(string: "00002902-0000-1000-8000-00805f9b34fb")

    // MARK: v1 / v2 / v4 / mini characteristics (app service, node 0001)
    static let charToken   = CBUUID(string: "d3c0ffa1-add3-1d4b-0001-0000b5006bb1") // token write
    static let charAuid    = CBUUID(string: "d3c0ffa2-add3-1d4b-0001-0000b5006bb1") // AUID write
    static let charState   = CBUUID(string: "d3c0ffa4-add3-1d4b-0001-0000b5006bb1") // state notify
    static let charEvent   = CBUUID(string: "d3c0ffa5-add3-1d4b-0001-0000b5006bb1") // touch/event notify
    static let charAppCmd  = CBUUID(string: "d3c0ffa6-add3-1d4b-0001-0000b5006bb1") // app command write (all non-v3)
    static let v1Ack       = CBUUID(string: "d3c0ffa7-add3-1d4b-0001-0000b5006bb1") // v1 command-result notify
    /// v4/mini: an encrypted characteristic — subscribing to it makes the phone bond.
    static let charBondNotify = CBUUID(string: "d3c0ffa8-add3-1d4b-0001-0000b5006bb1")

    // MARK: Service d3c00001 (node 0000)
    static let charApiVer  = CBUUID(string: "d3c0ffb3-add3-1d4b-0000-0000b5006bb1") // API-version read
    /// Battery: v2/v4/mini `[level %, reserved]`; v1 `[millivolts u16LE]`. Read + notify.
    static let charFF06    = CBUUID(string: "d3c0ff06-add3-1d4b-0000-0000b5006bb1")
    static let v1Firmware  = CBUUID(string: "d3c0ff03-add3-1d4b-0000-0000b5006bb1") // v1 `[patch, minor]`

    // MARK: v3 characteristics (service d3c00003, node 0000)
    static let v3ApiVer = CBUUID(string: "d3c0ff10-add3-1d4b-0000-0000b5006bb1")
    static let ffb1     = CBUUID(string: "d3c0ffb1-add3-1d4b-0000-0000b5006bb1") // app cmds + notify
    static let ffb2     = CBUUID(string: "d3c0ffb2-add3-1d4b-0000-0000b5006bb1") // touch pattern write

    /// Fixed app-layer pairing token used by the shipping firmware.
    static let token: [UInt8] = Array("12345678".utf8)

    /// Vibration strengths the bracelets accept (VibrationHelper); balance is 0…4, 2 = centre.
    static let vibrationLevels: [Int] = [28, 33, 40, 58, 60, 73, 80, 88, 100]

    // MARK: Names
    static let deviceNames = ["BOND", "Bond More", "BOND 4", "BOND MINI"]
    static let dfuNames = ["BOND_DFU", "BOND_M_DFU", "BOND_4_DFU", "BOND_MINI_DFU"]

    /// A normal (running) bracelet. Excludes bracelets in firmware-update (DFU) mode, and the
    /// Bond Heart pendant ("BondHeart" / "BOND_H_DFU"), which `HeartPendant` handles.
    static func isBondName(_ name: String?) -> Bool {
        guard let name else { return false }
        let upper = name.uppercased()
        if upper.hasPrefix("BONDHEART") || upper.hasPrefix("BOND_H_") { return false }
        return upper.hasPrefix("BOND") && dfuModel(name) == nil
    }

    /// The bracelet model of a bracelet stuck in firmware-update (DFU) mode, from the name
    /// its bootloader advertises: `BOND_DFU` (Bond Touch), `BOND_M_DFU` (Bond Touch More),
    /// `BOND_4_DFU` (Bond Touch 4), `BOND_MINI_DFU` (Bond Mini). Nil for anything else.
    static func dfuModel(_ name: String?) -> BraceletModel? {
        switch name?.uppercased() {
        case "BOND_DFU": return .bondTouch
        case "BOND_M_DFU": return .bondTouchMore
        case "BOND_4_DFU": return .bondTouch4
        case "BOND_MINI_DFU": return .bondMini
        default: return nil
        }
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
            // Exactly as the original app: [3] + "12345678", unpadded, and only when the
            // bracelet reports it is waiting for the token.
            return [(ffb1, Data(pfx(3) + token))]
        default:
            // v1 (WriteStringCommand) and v2-base (Q()): the bare 8 ASCII bytes on ffa1.
            return [(charToken, Data(token))]
        }
    }

    /// AUID write(s): the persisted per-install device/user id, little-endian u32.
    static func auidWrites(_ gen: BondGeneration, auid: UInt32) -> [(CBUUID, Data)] {
        switch gen {
        case .v3:
            // The Bond Touch More takes a single-byte AUID: [7, id], unpadded (original
            // app). Sending a 4-byte id padded to 20 bytes, as before, is not what its
            // firmware expects.
            let id = UInt8(truncatingIfNeeded: auid)
            return [(ffb1, Data([7, id == 0 ? 1 : id]))]
        default:
            return [(charAuid, Data(u32le(auid)))]
        }
    }

    // MARK: - LED + motor (notification buzz + glow)

    /// A buzz + glow in `rgb` (used for heartbeat pulses; not part of the original app).
    /// v2-base uses the 0x26 LED+motor frame; v3 the FFB1 colour + vibration commands. v1
    /// has its own sequenced frames (`V1Commands`).
    static func ledMotor(_ gen: BondGeneration, rgb: Int,
                         strength: UInt8 = 88, vibMs: UInt16 = 400,
                         brightness: UInt8 = 100, holdMs: UInt16 = 600) -> [(CBUUID, Data)] {
        switch gen {
        case .v3:
            // FFB1 commands are written at their exact length, as the original app does.
            let (r, g, b) = rgbBytes(rgb)
            return [(ffb1, Data([1, 0x4B, 0x00, 0x00, r, g, b])),
                    v3VibrationPreview(level: nearestVibrationLevel(Int(strength)), balance: 2)]
        case .v1:
            return []
        default:
            return [ledAndMotor(strength: strength, vibMs: vibMs, ledMode: 1, rgb: ledColor(rgb),
                                brightness: brightness, transitionMs: 80, holdMs: holdMs,
                                sleepMs: 80, executeMs: holdMs)]
        }
    }

    // MARK: - Light only (no motor) and the LED test queue — docs/FIRMWARE_LED_VIBE.md

    /// The band lit in `rgb` for `ms` without vibrating. v2/v4/Mini: a 0x26 frame with motor
    /// strength 0 (the firmware drives motor and LEDs separately). Bond Touch More: FFB1 0x4B,
    /// which never touches the motors (clear it with `v3LightOff`). Classic: not supported.
    static func lightOnly(_ gen: BondGeneration, rgb: Int, brightness: UInt8 = 80, ms: UInt16 = 1000) -> [(CBUUID, Data)] {
        switch gen {
        case .v3: return [v3Color(rgb)]
        case .v1: return []
        default:
            return [ledAndMotor(strength: 0, vibMs: 0, ledMode: 1, rgb: rgb, brightness: max(1, brightness),
                                transitionMs: 0, holdMs: ms, sleepMs: 0, executeMs: ms)]
        }
    }

    /// Bond Touch More: `[01 4B 01]` clears the colour set by 0x4B.
    static let v3LightOff: (CBUUID, Data) = (ffb1, Data([1, 0x4B, 0x01]))

    /// One heartbeat pulse: a short firm buzz + glow.
    static func heartbeatPulse(_ gen: BondGeneration, rgb: Int) -> [(CBUUID, Data)] {
        ledMotor(gen, rgb: rgb, strength: 100, vibMs: 130, brightness: 100, holdMs: 130)
    }

    /// The closest strength the bracelets accept.
    static func nearestVibrationLevel(_ x: Int) -> UInt8 {
        UInt8(vibrationLevels.min(by: { abs($0 - x) < abs($1 - x) }) ?? 80)
    }

    // MARK: - v2 / v4 / mini app commands (BleBondManagerV2Base, BleAppCommandHelper)

    /// v2-base frames are `Arrays.copyOf(frame, 20)`: zero-padded to 20 bytes, on ffa6.
    private static func app(_ bytes: [UInt8]) -> (CBUUID, Data) {
        (charAppCmd, Data(Array(bytes.prefix(20)) + Array(repeating: 0, count: max(0, 20 - bytes.count))))
    }

    /// 0x26 LedAndMotorCommand: `[0x26, 0, queue, strength, vibMs LE, ledMode, R, G, B,
    /// brightness, transition LE, hold LE, sleep LE, execute LE]`. ledMode 1 = solid,
    /// 2 = queued pattern step, 4 = off.
    static func ledAndMotor(queue: UInt8 = 0, strength: UInt8, vibMs: UInt16, ledMode: UInt8,
                            rgb: Int = 0, brightness: UInt8 = 0, transitionMs: UInt16 = 0,
                            holdMs: UInt16 = 0, sleepMs: UInt16 = 0, executeMs: UInt16 = 0) -> (CBUUID, Data) {
        let (r, g, b) = rgbBytes(rgb)
        var f: [UInt8] = [0x26, 0x00, queue, strength]
        f += u16le(safeMs(vibMs))
        f += [ledMode, r, g, b, safeBrightness(brightness)]
        f += u16le(safeMs(transitionMs))
        f += u16le(safeMs(holdMs))
        f += u16le(safeMs(sleepMs))
        f += u16le(safeMs(executeMs))
        return app(f)
    }

    /// 0x33 "send message" step (BleAppCommandHelper.a): `[0x33, 0, strength, brightness ×3,
    /// RGB1, RGB2, RGB3, ms LE16]`.
    private static func messageStep(_ rgb: Int, strength: UInt8, brightness: UInt8, ms: Int) -> (CBUUID, Data) {
        let level = safeBrightness(brightness)
        var f: [UInt8] = [0x33, 0x00, strength, level, level, level]
        f += be3(rgb) + be3(rgb) + be3(rgb)
        f += u16le(safeMs(UInt16(clamping: ms)))
        return app(f)
    }

    /// The firmware lights the LEDs only at brightness 1…100; 0 is off, and anything above
    /// 100 is also off (docs/FIRMWARE_LED_VIBE.md) — so cap at 100.
    static func safeBrightness(_ b: UInt8) -> UInt8 { min(b, 100) }

    /// A duration the Bond Touch's timer can start: 1–4 ms fails to start it and the bracelet
    /// reboots (docs/FIRMWARE_LED_VIBE.md), so those become 5 ms. 0 (none) stays 0.
    static func safeMs(_ ms: UInt16) -> UInt16 { (1...4).contains(ms) ? 5 : ms }

    /// 0x32 (BleAppCommandHelper.b): ends a queued message — 0x22 after 0x33 steps, 0x11
    /// after queued 0x26 frames. The original pauses its write queue 5 s once it's written.
    static func queueMarker(gradient: Bool) -> (CBUUID, Data) {
        app([0x32, 0x00, gradient ? 0x22 : 0x11])
    }

    /// 0x27 configuration write (BleAppCommandHelper.d): `[0x27, 0, property, 1, value…]`.
    private static func config(_ property: UInt8, _ value: [UInt8]) -> (CBUUID, Data) {
        app([0x27, 0x00, property, 0x01] + value)
    }

    /// A colour as the config commands carry it: the mapped ARGB int, big-endian (alpha 0xFF).
    private static func configColor(_ rgb: Int) -> [UInt8] {
        be32(0xFF00_0000 | UInt32(ledColor(rgb) & 0xFFFFFF))
    }

    /// A touch to play (BleBondManagerV2Base.g). One colour: queued 0x26 frames (queue 1),
    /// one per on/off pair, then `[0x32,0,0x11]`. A gradient: one 0x33 frame per 200 ms of
    /// each on segment (the original's `0..n` loop, so n+1 frames) shading start→end, a
    /// zero-colour 0x33 frame for each gap, then `[0x32,0,0x22]`. The mini always plays its
    /// fixed pattern (BleBondManagerMini.g); an empty pattern falls back to it too.
    static func v2TouchFrames(_ gen: BondGeneration, onOff raw: [Int], startRGB: Int, endRGB: Int,
                              strength: UInt8) -> [(CBUUID, Data)] {
        let list = gen == .mini || raw.isEmpty ? miniPattern : raw.map { max(0, $0) }
        if startRGB == endRGB {
            let rgb = ledColor(startRGB)
            var on: [Int] = [], off: [Int] = []
            for (i, ms) in list.enumerated() {
                if i % 2 == 0 { on.append(ms) } else { off.append(ms) }
            }
            if on.count > off.count { off.append(0) }
            var out: [(CBUUID, Data)] = on.indices.map { i -> (CBUUID, Data) in
                let o = on[i], f = off[i]
                let t = Int(Float(o) * 0.25)
                return ledAndMotor(queue: 1, strength: strength, vibMs: UInt16(clamping: o), ledMode: 2, rgb: rgb,
                                   brightness: 80, transitionMs: UInt16(clamping: t),
                                   holdMs: UInt16(clamping: o - t * 2), sleepMs: UInt16(clamping: f),
                                   executeMs: UInt16(clamping: o + f))
            }
            out.append(queueMarker(gradient: false))
            return out
        }
        let from = ledColor(startRGB), to = ledColor(endRGB)
        let total = Float(list.reduce(0, +))
        var elapsed: Float = 0
        var out: [(CBUUID, Data)] = []
        for (i, ms) in list.enumerated() {
            if i % 2 == 0 {
                let steps = max(1, Int(Float(ms) / 200))
                for _ in 0...steps {
                    let rgb = blend(from, to, total > 0 ? min(1, elapsed / total) : 0)
                    out.append(messageStep(rgb, strength: strength, brightness: 80, ms: 200))
                    elapsed += 200
                }
            } else {
                out.append(messageStep(0, strength: 0, brightness: 0, ms: ms))
                elapsed += Float(ms)
            }
        }
        out.append(queueMarker(gradient: true))
        return out
    }

    /// What the mini plays and reports for every touch (BleBondManagerMiniKt.b).
    static let miniPattern = [500, 250, 500, 250, 500]

    /// Written once the bracelet is bonded (BleBondManagerV2Base.D): low-battery alert at
    /// 10 %, blinking red 1000/500 ms; minimum touch 50 ms; "disconnected" params all zero.
    /// v2 also turns ANCS off (BleBondManagerV2.D).
    static func v2BondedSettings(_ gen: BondGeneration) -> [(CBUUID, Data)] {
        let lowBattery: [UInt8] = [1] + be16(1000) + be16(500) + be32(1171) + be32(0x00FF_0000)
        let disconnected: [UInt8] = [0] + be16(0) + be16(0) + be16(0) + be32(0)
        var out: [(CBUUID, Data)] = [
            config(0x17, [10]),             // LOW_BAT_THRESHOLD 10 %
            config(0x21, lowBattery),       // LOW_BAT_COLOR: on, 1000 / 500 ms, 1171, red
            config(0x14, u32le(50)),        // MIN_TOUCH_DURATION 50 ms (u32 little-endian)
            config(0x31, disconnected),     // DISCONNECTED_PARAM
        ]
        if gen == .v2 { out.append(v2Ancs(false)) }
        return out
    }

    /// ANCS_PARAM (0x33): whether the bracelet shows the phone's notifications.
    static func v2Ancs(_ on: Bool) -> (CBUUID, Data) { config(0x33, [on ? 1 : 0]) }

    /// MOTOR_STRENGTH (0x18) — BleBondManagerV2Base.B (balance isn't used on these models).
    static func v2MotorStrength(_ level: Int) -> (CBUUID, Data) { config(0x18, [UInt8(clamping: level)]) }

    /// The user's own colour (f()): TOUCH_COLOR, then on v2 DOUBLE_TAP_COLOR and on v4/mini
    /// the user's menu entry (UserMenu(colour, 0x80), also property 0x24).
    static func v2UserColor(_ gen: BondGeneration, rgb: Int) -> [(CBUUID, Data)] {
        let color = configColor(rgb)
        return [config(0x25, color),
                gen == .v2 ? config(0x24, color) : config(0x24, color + be32(0x80))]
    }

    /// One v4 partner-menu entry (BleBondManagerV4.W): UserMenu(colour, slot | 0x80) when
    /// active, UserMenu(0xFF000000, slot & 0x7F) when not.
    static func v2MenuEntry(slot: Int, rgb: Int?) -> (CBUUID, Data) {
        if let rgb { return config(0x24, configColor(rgb) + be32(UInt32(slot | 0x80))) }
        return config(0x24, be32(0xFF00_0000) + be32(UInt32(slot & 0x7F)))
    }

    /// SELECTED_USER (0x37): which partner slot (1…3) the v4 sends to.
    static func v2SelectedUser(_ slot: Int) -> (CBUUID, Data) { config(0x37, [UInt8(clamping: slot)]) }

    /// The answer to the PAIRED_SIGNAL event (0x13).
    static let v2PairedReply: (CBUUID, Data) = app([0x31, 0x00, 0x11, 0x22, 0x33, 0x44])

    /// Vibration preview (BleBondManagerV2Base.z): motor only, 2 s.
    static func v2VibrationPreview(level: Int) -> (CBUUID, Data) {
        ledAndMotor(strength: UInt8(clamping: level), vibMs: 2000, ledMode: 4)
    }

    /// Colour preview (y()): hold `rgb` until told otherwise (execute 0xFFFF).
    static func v2HoldColor(_ rgb: Int) -> (CBUUID, Data) {
        ledAndMotor(strength: 0, vibMs: 0, ledMode: 1, rgb: ledColor(rgb), brightness: 80, executeMs: 0xFFFF)
    }

    /// LEDs off (h()).
    static let v2LedsOff: (CBUUID, Data) = ledAndMotor(strength: 0, vibMs: 0, ledMode: 4)

    /// Restarts a v2 / v4 / mini in its update (DFU) bootloader (BleBondManagerV2Base.C,
    /// "startDfuMode"): `[0x25, 0x00, 0x11, 0x22, 0x33, 0x44]`, zero-padded to 20, on ffa6.
    static let v2EnterUpdateMode: (CBUUID, Data) = app([0x25, 0x00, 0x11, 0x22, 0x33, 0x44])

    /// The state characteristic (ffa4): `[bondState, chargingState, ledBusy, motorBusy, touchBusy]`.
    /// Bond states 0x82 WAITING_TOKEN, 0x83 WAITING_AUID, 0x84 OOBE (setup), 0x85 CONNECTED,
    /// 0x86 MSG, 0x87 FACTORY, 0x88 QUEUE_EXECUTING; charging 0 no, 1 charging, 2 full, 0xFF error.
    struct V2State {
        let bond: UInt8
        let charging: UInt8
        init?(_ data: Data) {
            let b = [UInt8](data)
            guard b.count >= 5 else { return nil }
            bond = b[0]; charging = b[1]
        }
    }

    /// A v2-base AppEvent from the event characteristic (ffa5).
    enum V2Event {
        case auidError
        case pairedSignal
        /// A recorded touch segment; `slot` is the v4 partner slot it's for (byte 14).
        case segment(touchMs: Int, releaseMs: Int, counter: Int, stop: Bool, slot: Int)
        case timeout(counter: Int, slot: Int)
        case tap
        case doubleTap
        case ignored
    }

    /// Parses `[eventId, counter, touchMs u32LE, releaseMs u32LE, stop u32LE, (v4) slot]`.
    static func v2Event(_ data: Data) -> V2Event {
        let b = [UInt8](data)
        // A 0x19 blob of length >= 14 is a ship-mode / BLE-params report, not an event.
        guard b.count >= 14, b[0] != 0x19 else { return .ignored }
        let counter = Int(b[1])
        let slot = b.count > 14 ? Int(b[14]) : 0
        switch b[0] {
        case 0x12: return .auidError
        case 0x13: return .pairedSignal
        case 0x14:
            return .segment(touchMs: Int(u32leAt(b, 2)), releaseMs: Int(u32leAt(b, 6)), counter: counter,
                            stop: u32leAt(b, 10) == 0xFFFF_FFFF, slot: slot)
        case 0x15: return .timeout(counter: counter, slot: slot)
        case 0x16: return .tap
        case 0x17: return .doubleTap
        default:   return .ignored
        }
    }

    // MARK: - v1 commands (BleBondManagerV1, v1.BleAppCommandHelper, WriteFF06Command)

    /// v1 frames on d3c0ffa6: `[opcode u16LE, seq u16LE, …]`, 16 bytes (8 for the short ones),
    /// zero-filled, numbered with a running sequence that wraps after 65535.
    struct V1Commands {
        private var seq = 0

        private mutating func next() -> [UInt8] {
            seq += 1
            if seq > 65535 { seq = 0 }
            return BondGATT.u16le(UInt16(seq))
        }

        private static func frame(_ b: [UInt8], _ length: Int) -> (CBUUID, Data) {
            (BondGATT.charAppCmd, Data(b + Array(repeating: 0, count: max(0, length - b.count))))
        }

        /// 0x26 LgtVibCommand: `[ledId, mode, kind, 1, (100, steps u16LE)]`.
        private mutating func lgtVib(_ led: UInt8, mode: UInt8, kind: UInt8, timing: (UInt16, UInt16)?) -> (CBUUID, Data) {
            var b = BondGATT.u16le(38) + next() + [led, mode, kind, 1]
            if let t = timing { b += BondGATT.u16le(t.0) + BondGATT.u16le(t.1) }
            return Self.frame(b, 16)
        }

        /// A touch (g()): one LgtVib per on/off entry — modes alternating 2, 1, … — then a
        /// closing frame (mode 2, kind 2, no timing).
        mutating func touch(onOff: [Int], rgb: Int) -> [(CBUUID, Data)] {
            let led = BondGATT.v1Led(rgb)
            var out: [(CBUUID, Data)] = []
            var second = false
            for ms in onOff {
                let steps = (max(100, ms) * 10) / led.steps
                out.append(lgtVib(led.id, mode: second ? 1 : 2, kind: 1,
                                  timing: (100, UInt16(truncatingIfNeeded: steps))))
                second.toggle()
            }
            out.append(lgtVib(led.id, mode: 2, kind: 2, timing: nil))
            return out
        }

        /// 0x27 ActConfigCommand `[param u32LE, value u32LE]`.
        private mutating func actConfig(_ param: UInt32, _ value: UInt32) -> (CBUUID, Data) {
            Self.frame(BondGATT.u16le(39) + next() + BondGATT.u32le(param) + BondGATT.u32le(value), 16)
        }

        /// The user's colour (f()): colour 1003, LED id 1006, then save (0x27, 1000, 8 bytes).
        mutating func userColor(_ rgb: Int) -> [(CBUUID, Data)] {
            let led = BondGATT.v1Led(rgb)
            let color = actConfig(1003, BondGATT.v1Palette(led.id))
            let id = actConfig(1006, UInt32(led.id))
            let save = Self.frame(BondGATT.u16le(39) + next() + BondGATT.u32le(1000), 8)
            return [color, id, save]
        }

        /// 0x21 ColorCommand `[colour u32LE, with byte 7 = 100]`.
        private mutating func color(_ argb: UInt32) -> (CBUUID, Data) {
            var b = BondGATT.u16le(33) + next() + BondGATT.u32le(argb)
            b[7] = 100
            return Self.frame(b, 16)
        }

        /// Shows a colour (y()).
        mutating func previewColor(_ rgb: Int) -> (CBUUID, Data) { color(BondGATT.v1Palette(BondGATT.v1Led(rgb).id)) }
        /// LEDs off (h()).
        mutating func colorOff() -> (CBUUID, Data) { color(0) }

        /// 0x25 DfuCommand (C()): `[0x25, 0, seq, 0xFFFFFFFF]`, 8 bytes — restarts the
        /// bracelet in its update bootloader.
        mutating func enterUpdateMode() -> (CBUUID, Data) {
            Self.frame(BondGATT.u16le(37) + next() + [0xFF, 0xFF, 0xFF, 0xFF], 8)
        }
    }

    /// The answer to the v1 PAIRED_SIGNAL event (19): a single byte 0x31 on ffa6.
    static let v1PairedReply: (CBUUID, Data) = (charAppCmd, Data([0x31]))

    /// v1 state (ffa4): `[bondEvent, pairedEvent, charging]` — paired 244 = waiting for the
    /// AUID, 246 = connected, 247 = busy (message).
    struct V1State {
        let paired: UInt8
        let charging: UInt8
        init?(_ data: Data) {
            let b = [UInt8](data)
            guard b.count >= 3 else { return nil }
            paired = b[1]; charging = b[2]
        }
    }

    /// v1 event (ffa5): `[id, counter, count u16LE, touchMs u16LE]` — 18 AUID error,
    /// 19 paired signal, 20 touch (count 1 = first, 0xFFFE timeout, 0xFFFF end).
    struct V1Event {
        let id: UInt8
        let count: Int
        let touchMs: Int
        init?(_ data: Data) {
            let b = [UInt8](data)
            guard b.count >= 6 else { return nil }
            id = b[0]
            count = Int(b[2]) | Int(b[3]) << 8
            touchMs = Int(b[4]) | Int(b[5]) << 8
        }
    }

    /// v1 battery (ff06): millivolts → % over 3.7…4.1 V.
    static func v1BatteryPercent(_ data: Data) -> Int? {
        let b = [UInt8](data)
        guard b.count >= 2 else { return nil }
        let mv = Int(b[0]) | Int(b[1]) << 8
        return max(0, min(400, mv - 3700)) * 100 / 400
    }

    /// The v1 LED for a colour: ColorMapperHelper.a snaps it to the base palette, then the
    /// palette colour's LED id and step length (default LED 1, 100).
    static func v1Led(_ rgb: Int) -> (id: UInt8, steps: Int) {
        let base = v1BaseColor[rgb & 0xFFFFFF] ?? 0x23E0E8
        return v1LedIDs[base] ?? (1, 100)
    }

    /// BleColorTable: the ARGB colour of each v1 LED id (‑1 for an unknown id).
    static func v1Palette(_ id: UInt8) -> UInt32 {
        let table: [UInt32] = [0xFF0000, 0x00EEF9, 0x000FF9, 0xBA00F9, 0xF9002D, 0x07F900,
                               0x61F900, 0xF9F500, 0xF94300, 0xFFFFFF, 0x000000]
        return Int(id) < table.count ? 0xFF00_0000 | table[Int(id)] : 0xFFFF_FFFF
    }

    private static let v1LedIDs: [Int: (id: UInt8, steps: Int)] = [
        0xFF0000: (0, 30), 0x23E0E8: (1, 100), 0x106DED: (2, 100), 0xBE5BFF: (3, 100), 0xA502C0: (3, 100),
        0xFF44A6: (4, 100), 0x03AB55: (5, 100), 0x7BBE2F: (6, 100), 0xE8D726: (7, 100), 0xFF7931: (8, 100),
        0xFFFFFF: (9, 100), 0x000000: (10, 100),
    ]

    /// ColorMapperHelper.a: app colour → base palette colour (v1).
    private static let v1BaseColor: [Int: Int] = [
        0x23E0E8: 0x23E0E8, 0x106DED: 0x106DED, 0xBE5BFF: 0xBE5BFF, 0xFF44A6: 0xFF44A6, 0x03AB55: 0x03AB55,
        0x7BBE2F: 0x7BBE2F, 0xE8D726: 0xE8D726, 0xFF7931: 0xFF7931, 0xA502C0: 0xA502C0, 0xD3007A: 0xFF44A6,
        0xD33901: 0xFF7931, 0xFF7C00: 0xFF7931, 0xEFAE1D: 0xFF7931, 0xFFE700: 0xE8D726, 0xE4FF02: 0xE8D726,
        0xAFFF00: 0xE8D726, 0x79FF03: 0x7BBE2F, 0x00D600: 0x7BBE2F, 0x00B560: 0x03AB55, 0x01D3B1: 0x03AB55,
        0x28E4EB: 0x23E0E8, 0x00A4D3: 0x23E0E8, 0x006BD3: 0x106DED, 0x0045D2: 0x106DED, 0x1800C8: 0x106DED,
        0x6D3DC9: 0xBE5BFF, 0x9D03DD: 0xBE5BFF, 0xC300D3: 0xBE5BFF, 0xD301AA: 0xFF44A6, 0xFA3A96: 0xFF44A6,
        0xFF5338: 0xFF7931, 0xFF7701: 0xFF7931, 0xFFA910: 0xFF7931, 0xFFCD00: 0xE8D726, 0xFFE804: 0xE8D726,
        0xEDFF04: 0xE8D726, 0xB6FF01: 0x7BBE2F, 0x5FF540: 0x7BBE2F, 0x05EB79: 0x03AB55, 0x2EF3BC: 0x03AB55,
        0x51FBF3: 0x23E0E8, 0x22E7FF: 0x23E0E8, 0x00C8FF: 0x106DED, 0x009FFF: 0x106DED, 0x1875FF: 0x106DED,
        0x8E59FF: 0xBE5BFF, 0xB659FF: 0xBE5BFF, 0xF25BFF: 0xBE5BFF, 0xF44CCE: 0xFF44A6,
    ]

    /// ColorMapperHelper.b: the app's palette colours → the LED colours v2/v4/mini show
    /// (anything else is sent as is).
    static func ledColor(_ rgb: Int) -> Int { ledColorMap[rgb & 0xFFFFFF] ?? (rgb & 0xFFFFFF) }

    private static let ledColorMap: [Int: Int] = [
        0xFA3A96: 0xD30013, 0xFF5338: 0xFF0C00, 0xFF7701: 0xFF2200, 0xFFA910: 0xF83C00, 0xFFCD00: 0xF85000,
        0xFFE804: 0xF89200, 0xEDFF04: 0xDDC500, 0xB6FF01: 0x9FC500, 0x5FF540: 0x58B800, 0x05EB79: 0x087100,
        0x2EF3BC: 0x08FB35, 0x51FBF3: 0x6DF7E3, 0x22E7FF: 0x00B7D3, 0x00C8FF: 0x006BD3, 0x009FFF: 0x0032D3,
        0x1875FF: 0x000078, 0x8E59FF: 0x6500D3, 0xB659FF: 0xB100D3, 0xF25BFF: 0xD30072, 0xF44CCE: 0xD30039,
        0xD3007A: 0xD30013, 0xD33901: 0xFF0C00, 0xFF7C00: 0xFF2200, 0xEFAE1D: 0xF83C00, 0xFFE700: 0xF85000,
        0xE4FF02: 0xF89200, 0xAFFF00: 0xDDC500, 0x79FF03: 0x9FC500, 0x00D600: 0x58B800, 0x00B560: 0x087100,
        0x01D3B1: 0x08FB35, 0x28E4EB: 0x6DF7E3, 0x00A4D3: 0x00B7D3, 0x006BD3: 0x006BD3, 0x0045D2: 0x0032D3,
        0x1800C8: 0x000078, 0x6D3DC9: 0x6500D3, 0x9D03DD: 0xB100D3, 0xC300D3: 0xD30072, 0xD301AA: 0xD30039,
    ]

    /// Linear blend per channel, truncated (the original's ArgbEvaluator-style sb1.b).
    private static func blend(_ a: Int, _ b: Int, _ t: Float) -> Int {
        func ch(_ shift: Int) -> Int {
            Int(Float((b >> shift) & 0xFF) * t + Float((a >> shift) & 0xFF) * (1 - t))
        }
        return (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }

    /// What the original app sends once a Bond Touch More reports CONNECTED: enables its
    /// touch and event features (0x19, 0x1B, 0x41, 0x42, [0x49, 1], 0x1C).
    static let v3ConnectedWrites: [(CBUUID, Data)] = [
        [1, 0x19], [1, 0x1B], [1, 0x41], [1, 0x42], [1, 0x49, 0x01], [1, 0x1C]
    ].map { (ffb1, Data($0)) }

    // MARK: - Bond Touch More session commands (from the original app's BleBondManagerV3)

    /// Asks for the firmware version (answered with an 0xAC notification). The original
    /// sends it right after enabling FFB1 notifications; the answer is what marks the
    /// bracelet as paired, after which settings go out.
    static let v3FirmwareRequest: (CBUUID, Data) = (ffb1, Data([1, 0x30]))
    /// "Paired" confirmation — the answer to WAIT_FOR_ACT_PAIRED (state 138) and to the
    /// PAIRED signal (event 19). Without it the bracelet sits flashing white and drops the link.
    static let v3PairedConfirm: (CBUUID, Data) = (ffb1, Data([1, 0x31]))
    /// Asks for the three partner slots currently on the bracelet (answered with an ack
    /// `[0x0A, 0x45, 3 × (state, R, G, B)]`).
    static let v3ReadUserColors: (CBUUID, Data) = (ffb1, Data([1, 0x45, 0x01]))

    /// One partner slot in the bracelet's menu: its colour lights the bar and marks which
    /// partner a touch is from or to. A bracelet with no active slot shows no colours and
    /// won't record a touch.
    struct V3Slot: Equatable {
        enum State: UInt8 { case inactive = 0, active = 1, ignore = 2 }
        var state: State
        var rgb: Int
        static let inactive = V3Slot(state: .inactive, rgb: 0x000000)
        var bytes: [UInt8] { [state.rawValue, UInt8((rgb >> 16) & 0xFF), UInt8((rgb >> 8) & 0xFF), UInt8(rgb & 0xFF)] }
    }

    /// Writes the three partner slots: `[1, 0x45, 0x00, slot1, slot2, slot3]`, each slot
    /// `[state, R, G, B]` (state 2 = leave that slot as it is).
    static func v3WriteUserColors(_ slots: [V3Slot]) -> (CBUUID, Data) {
        let three = Array((slots + Array(repeating: V3Slot.inactive, count: 3)).prefix(3))
        return (ffb1, Data([1, 0x45, 0x00] + three.flatMap(\.bytes)))
    }

    /// Parses the slots from a user-colour ack `[0x0A, 0x45, s, r, g, b, s, r, g, b, s, r, g, b]`.
    static func v3UserColors(fromAck b: [UInt8]) -> [V3Slot]? {
        guard b.count >= 14, b[0] == 0x0A, b[1] == 0x45 else { return nil }
        return (0..<3).map { i in
            let o = 2 + i * 4
            return V3Slot(state: V3Slot.State(rawValue: b[o]) ?? .ignore,
                          rgb: (Int(b[o + 1]) << 16) | (Int(b[o + 2]) << 8) | Int(b[o + 3]))
        }
    }

    /// Vibration strength and left/right balance: `[1, 0x48, 0x02, level, balance, 0x03]`
    /// (BleBondManagerV3.F). Valid levels 28, 33, 40, 58, 60, 73, 80, 88, 100; balance 0…4
    /// (2 = centred).
    static func v3Vibration(level: UInt8, balance: UInt8) -> (CBUUID, Data) {
        (ffb1, Data([1, 0x48, 0x02, level, balance, 0x03]))
    }

    /// Plays a vibration once without saving it: `[1, 0x48, 0x00, level, balance, 0x03]` (z()).
    static func v3VibrationPreview(level: UInt8, balance: UInt8) -> (CBUUID, Data) {
        (ffb1, Data([1, 0x48, 0x00, level, balance, 0x03]))
    }

    /// Lights the whole bar in a colour: `[1, 0x4B, 0x00, 0x00 (all LEDs), R, G, B]` (y()).
    static func v3Color(_ rgb: Int) -> (CBUUID, Data) {
        (ffb1, Data([1, 0x4B, 0x00, 0x00] + be3(rgb)))
    }

    /// One heartbeat on a Bond Touch More bar: a 200 ms spike — up to the top of the bar and
    /// down to the bottom (the EKG's R and S) — the only part that vibrates; between beats
    /// the band just glows (`v3Color`).
    static func v3HeartbeatSpike(rgb: Int) -> [(CBUUID, Data)] {
        v3TouchFrames(samples: [6, 8, 0, 2].map { TouchPattern.sample([$0]) }, startRGB: rgb, endRGB: rgb)
    }

    /// LEDs off: `[1, 0x4B, 0x01]` (h()).
    static let v3LedsOff: (CBUUID, Data) = (ffb1, Data([1, 0x4B, 0x01]))

    /// Restarts a Bond Touch More in its update bootloader, as the original's C(): the
    /// firmware request `[1, 0x30]` (J()), then `[1, 0x2A]`, both at their exact length.
    static let v3EnterUpdateMode: [(CBUUID, Data)] = [v3FirmwareRequest, (ffb1, Data([1, 0x2A]))]

    /// The bracelet's battery-alert settings, from the ack `[0x0A, 0x49, low %, R, G, B,
    /// critical %, R, G, B]` (asked for by the `[1, 0x49, 1]` sent on CONNECTED).
    struct BatteryAlertSettings: Equatable {
        let lowPercent: Int
        let lowRGB: Int
        let criticalPercent: Int
        let criticalRGB: Int

        init?(v3Ack b: [UInt8]) {
            guard b.count >= 10, b[0] == 0x0A, b[1] == 0x49 else { return nil }
            lowPercent = Int(b[2])
            lowRGB = (Int(b[3]) << 16) | (Int(b[4]) << 8) | Int(b[5])
            criticalPercent = Int(b[6])
            criticalRGB = (Int(b[7]) << 16) | (Int(b[8]) << 8) | Int(b[9])
        }
    }

    /// A whole heartbeat for a Bond Touch More as ONE touch message, shaped like a real
    /// heart: each beat is a big "lub" (the whole bar lights and both motors buzz, 150 ms)
    /// then, ~150 ms later, a smaller "dub" (just the centre, 100 ms), then a rest to the
    /// next beat. At most 10 s (200 samples); light and vibration render in sync.
    static func v3Heartbeat(bpm: Int, seconds: Double, rgb: Int) -> [(CBUUID, Data)] {
        let period = max(3, Int((60.0 / Double(max(bpm, 30))) * 1000) / TouchPattern.sampleMs)
        let total = min(TouchPattern.maxSamples, Int(seconds * 1000) / TouchPattern.sampleMs)
        let fullBar = (8 << 4) | 0   // two "fingers" at 0 and 8: the whole bar (the big lub)
        let centre = 0xF0 | 4        // one finger at the centre: the small dub
        let lub = 3, gap = 3, dub = 2
        var samples: [Int] = []
        while samples.count < total {
            if period >= lub + gap + dub + 1 {
                samples += Array(repeating: fullBar, count: lub)
                samples += Array(repeating: TouchPattern.none, count: gap)
                samples += Array(repeating: centre, count: dub)
                samples += Array(repeating: TouchPattern.none, count: period - lub - gap - dub)
            } else {
                // Too fast to fit a lub-dub; one beat per period.
                samples += Array(repeating: fullBar, count: min(lub, period))
                samples += Array(repeating: TouchPattern.none, count: max(0, period - lub))
            }
        }
        return v3TouchFrames(samples: Array(samples.prefix(total)), startRGB: rgb, endRGB: rgb)
    }

    // MARK: - Sending a touch (replay the tap rhythm)

    /// Plays a touch on the bracelet.
    /// v3 (Bond Touch More): the 50 ms position samples on FFB2 — the bar lights and the
    /// vibration pans along the positions. v2-base: `v2TouchFrames` at the user's vibration
    /// strength. v1 frames are sequenced, so `V1Commands.touch` builds them instead.
    static func touchSend(_ gen: BondGeneration, touch: TouchMessage, slot: Int = 1,
                          strength: Int = 80) -> [(CBUUID, Data)] {
        switch gen {
        case .v3:
            return v3TouchFrames(samples: touch.samples, startRGB: touch.colorRGB, endRGB: touch.endColorRGB, slot: slot)
        case .v1:
            return []
        default:
            return v2TouchFrames(gen, onOff: touch.onOffMs, startRGB: touch.colorRGB, endRGB: touch.endColorRGB,
                                 strength: UInt8(clamping: strength))
        }
    }

    /// FFB2 playback (BleBondManagerV3.g): header `[partner slot 1…3, n, ceil(n/20), colour1
    /// RGB, colour2 RGB, reply 0]` padded with 0xFF, then the sample bytes 20 per packet,
    /// padded with 0xFF. Colours go as is (no colour mapping on v3); the reply flag is 0 for
    /// a received touch. The firmware accepts 1…10 packets, so at most 200 samples.
    private static func v3TouchFrames(samples raw: [Int], startRGB: Int, endRGB: Int, slot: Int = 1) -> [(CBUUID, Data)] {
        var samples = TouchPattern.trimmed(raw).map { UInt8(clamping: $0) }
        if samples.isEmpty { samples = [0xF4, 0xF4, 0xF4, 0xF4] }   // a short centre tap
        let chunks = (samples.count + 19) / 20
        let header: [UInt8] = [UInt8(min(max(slot, 1), 3)), UInt8(samples.count), UInt8(chunks)]
            + be3(startRGB) + be3(endRGB) + [0x00]
        var frames: [(CBUUID, Data)] = [(ffb2, padFF(header))]
        var idx = 0
        while idx < samples.count {
            frames.append((ffb2, padFF(Array(samples[idx..<min(idx + 20, samples.count)]))))
            idx += 20
        }
        return frames
    }

    private static func padFF(_ bytes: [UInt8]) -> Data {
        Data(bytes + Array(repeating: 0xFF, count: max(0, 20 - bytes.count)))
    }

    /// Reassembles a touch recorded on the Bond Touch More bar from FFB2 notifications:
    /// a header `[slot 1…3, n, packets, …]` then `packets` × 20 sample bytes.
    struct V3Recording {
        private var expected = 0
        private var slot = 1
        private var bytes: [Int] = []

        /// Feeds one FFB2 notification; when complete, returns the partner slot (1…3) the
        /// touch is for and its trimmed samples.
        mutating func feed(_ data: Data) -> (slot: Int, samples: [Int])? {
            let b = [UInt8](data)
            if expected == 0 {
                guard b.count >= 3, (1...3).contains(b[0]), (1...10).contains(b[2]) else { return nil }
                slot = Int(b[0]); expected = Int(b[2]); bytes = []
                return nil
            }
            guard b.count >= 20 else { expected = 0; bytes = []; return nil }
            bytes += b.prefix(20).map(Int.init)
            expected -= 1
            guard expected == 0 else { return nil }
            let out = TouchPattern.trimmed(bytes)
            bytes = []
            return out.isEmpty ? nil : (slot, out)
        }
    }

    // MARK: - Byte helpers
    private static func pfx(_ p: UInt8) -> [UInt8] { [p] }
    static func u16le(_ x: UInt16) -> [UInt8] { [UInt8(x & 0xFF), UInt8((x >> 8) & 0xFF)] }
    static func u32le(_ x: UInt32) -> [UInt8] {
        [UInt8(x & 0xFF), UInt8((x >> 8) & 0xFF), UInt8((x >> 16) & 0xFF), UInt8((x >> 24) & 0xFF)]
    }
    static func be16(_ x: UInt16) -> [UInt8] { [UInt8((x >> 8) & 0xFF), UInt8(x & 0xFF)] }
    static func be32(_ x: UInt32) -> [UInt8] {
        [UInt8((x >> 24) & 0xFF), UInt8((x >> 16) & 0xFF), UInt8((x >> 8) & 0xFF), UInt8(x & 0xFF)]
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
}

/// A firmware version as the original compares them (FirmwareVersion): three numbers,
/// compared in order. A two-part string is a classic v1's "minor.patch" in hex ("2.60" =
/// 1.2.96); anything else is 0.0.0 — unknown, never offered an update (FirmwareHelper.a).
struct BondFirmwareVersion: Comparable, CustomStringConvertible {
    let major: Int, minor: Int, patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major; self.minor = minor; self.patch = patch
    }

    init(_ string: String) {
        let parts = string.split(separator: ".").map(String.init)
        if parts.count == 3, let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) {
            self.init(a, b, c)
        } else if parts.count == 2, let b = Int(parts[0], radix: 16), let c = Int(parts[1], radix: 16) {
            self.init(1, b, c)
        } else {
            self.init(0, 0, 0)
        }
    }

    var isUnknown: Bool { major == 0 && minor == 0 && patch == 0 }
    var description: String { "\(major).\(minor).\(patch)" }

    static func < (a: BondFirmwareVersion, b: BondFirmwareVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

extension BondGeneration {
    /// The newest firmware the original app ships for this generation (each manager's
    /// "supported version", BleBondClient.Companion.a) and the bundled file that holds it
    /// (DfuUpdateViewModel.n: BT1 → dfu_v260_hw203, BT2 → dfu_v279_hw2g, BTM → dfu_v311_hw3g,
    /// BT4 → dfu_v203_hw4g, mini → dfu_v120_hwmini). Both classic v1 and v2 restart as
    /// BOND_DFU; the v1's image is the older-hardware one ("2.60" = 1.2.96).
    var latestFirmware: (model: BraceletModel, version: BondFirmwareVersion, file: String) {
        switch self {
        case .v1:   return (.bondTouch, BondFirmwareVersion(1, 2, 96), "bondTouch-hw203")
        case .v2:   return (.bondTouch, BondFirmwareVersion(2, 7, 9), "bondTouch")
        case .v3:   return (.bondTouchMore, BondFirmwareVersion(3, 1, 1), "bondTouchMore")
        case .v4:   return (.bondTouch4, BondFirmwareVersion(2, 0, 3), "bondTouch4")
        case .mini: return (.bondMini, BondFirmwareVersion(1, 2, 0), "bondMini")
        }
    }
}

/// Bracelet models, as far as firmware recovery is concerned (one firmware per model).
enum BraceletModel: String, CaseIterable, Codable, Identifiable {
    case bondTouchMore, bondTouch, bondTouch4, bondMini
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bondTouchMore: return "Bond Touch More"
        case .bondTouch: return "Bond Touch"
        case .bondTouch4: return "Bond Touch 4"
        case .bondMini: return "Bond Mini"
        }
    }

    /// The name the bracelet advertises when stuck in update mode.
    var dfuName: String {
        switch self {
        case .bondTouchMore: return "BOND_M_DFU"
        case .bondTouch: return "BOND_DFU"
        case .bondTouch4: return "BOND_4_DFU"
        case .bondMini: return "BOND_MINI_DFU"
        }
    }

    /// A best guess from a firmware file's name (the official files are named after the
    /// model, e.g. `dfu_v3.1.1.zip` for the Bond Touch More).
    static func guess(fromFileName name: String) -> BraceletModel? {
        let n = name.uppercased()
        if n.contains("M_DFU") || n.contains("MORE") || n.contains("V3.1") || n.contains("HW3G") || n.contains("V311") { return .bondTouchMore }
        if n.contains("MINI") { return .bondMini }
        if n.contains("BOND_4") || n.contains("DFU_4") || n.contains("TOUCH 4") || n.contains("HW4G") { return .bondTouch4 }
        if n.contains("2G") || n.contains("V279") || n.contains("V260") || n.contains("HW203") || n.contains("BOND_DFU") { return .bondTouch }
        return nil
    }
}
