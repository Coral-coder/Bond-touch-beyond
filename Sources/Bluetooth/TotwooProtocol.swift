import CoreBluetooth
import Foundation

/// totwoo jewellery ("TWO" / "LCT" line, Nordic-based) — GATT layout and wire codec, as the
/// totwoo app 4.7.7 speaks it (docs/TOTWOO_BLE_PROTOCOL.md).
///
/// A command is a logical packet — a 16-bit index, a command id (category) and TLV segments
/// whose `type` is the real operation — framed for BLE as `FF hdr len payload… sum`, split into
/// 20-byte writes when the payload is over 16 bytes. The checksum is a plain 8-bit sum.
enum TotwooGATT {
    // Three vendor services, each with an even (write) / odd (notify) characteristic pair.
    static let services = [CBUUID(string: "FD18"), CBUUID(string: "FD08"), CBUUID(string: "FD28")]
    /// Primary command channel (most commands) and its notify.
    static let write = CBUUID(string: "FD1A")
    static let notify = CBUUID(string: "FD19")
    static let write2 = CBUUID(string: "FD0A")
    static let notify2 = CBUUID(string: "FD09")
    static let write3 = CBUUID(string: "FD2A")
    static let notify3 = CBUUID(string: "FD29")
    /// Realtime / raw sensor stream (notifications on).
    static let stream = CBUUID(string: "2AF0")

    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    static let infoService = CBUUID(string: "180A")
    static let modelNumber = CBUUID(string: "2A24")
    static let serialNumber = CBUUID(string: "2A25")
    static let hardwareRevision = CBUUID(string: "2A27")
    static let softwareRevision = CBUUID(string: "2A28")

    /// Whether an advertisement looks like totwoo jewellery: one of its vendor services, or a
    /// name the line uses.
    static func looksLikeTotwoo(name: String?, services: [CBUUID]) -> Bool {
        if services.contains(where: { Self.services.contains($0) }) { return true }
        let n = (name ?? "").lowercased()
        return n.contains("totwoo") || n.hasPrefix("two") || n.hasPrefix("lct") || n.hasPrefix("tw-") || n.hasPrefix("tw_")
    }
}

enum TotwooProtocol {
    /// One TLV segment: the operation (`type`) and its value.
    struct Segment: Equatable {
        var type: UInt8
        var value: [UInt8]
    }

    /// A logical command or response.
    struct Packet: Equatable {
        var index: UInt16
        var command: UInt8
        var isReply = false
        var segments: [Segment]
    }

    /// Constant tag after the command id (payload[3]).
    static let marker: UInt8 = 0x18
    static let maxChunk = 16

    // MARK: Commands (phone → device)

    /// Set the time: local-time epoch seconds, 4 bytes big-endian (§3 step 5).
    static func setTime(_ date: Date = Date(), timeZone: TimeZone = .current) -> (UInt8, [Segment]) {
        let local = UInt32(truncatingIfNeeded: Int(date.timeIntervalSince1970) + timeZone.secondsFromGMT(for: date))
        return (0x01, [Segment(type: 0x03, value: be32(local))])
    }

    /// The "totwoo" notify event: the jewellery lights in `rgb` (and vibrates) in the style the
    /// two mode bytes pick (§6, command 0x02 type 0x01).
    static func notify(rgb: Int, mode: UInt8, style: UInt8) -> (UInt8, [Segment]) {
        (0x02, [Segment(type: 0x01, value: [mode, style] + rgb24(rgb))])
    }

    /// Trigger a vibration / alert pattern (find-device etc.; §6, 0x02 / 0x07).
    static func vibrate(pattern: UInt8) -> (UInt8, [Segment]) {
        (0x02, [Segment(type: 0x07, value: [pattern])])
    }

    /// The colour the jewellery uses for touch / tap notifications (§6, 0x01 / 0x16).
    static func setTouchColor(_ rgb: Int) -> (UInt8, [Segment]) {
        (0x01, [Segment(type: 0x16, value: [0x03] + rgb24(rgb))])
    }

    /// Acknowledges a sleep (`type` 0x01) or activity (0x03) upload block, echoing its counter.
    static func ack(type: UInt8, counter: [UInt8]) -> (UInt8, [Segment]) {
        (0x04, [Segment(type: type, value: counter)])
    }

    // MARK: Encode

    /// The inner payload: index (little-endian), command id, the 0x18 tag, then each segment as
    /// `type, 00, len, value…`.
    static func payload(_ p: Packet) -> [UInt8] {
        var out: [UInt8] = [UInt8(p.index & 0xFF), UInt8(p.index >> 8), p.command, marker]
        for s in p.segments { out += [s.type, 0x00, UInt8(clamping: s.value.count)] + s.value }
        return out
    }

    /// The GATT writes for a packet: one frame when the payload fits in 16 bytes, else 20-byte
    /// fragments (header bit 7 = fragmented, bit 6 = final).
    static func frames(_ p: Packet) -> [[UInt8]] {
        let inner = payload(p)
        if inner.count <= maxChunk {
            let frame = [0xFF, 0x00, UInt8(inner.count + 4)] + inner
            return [frame + [checksum(frame)]]
        }
        var out: [[UInt8]] = []
        var i = 0, offset = 0
        while offset < inner.count {
            let chunk = Array(inner[offset ..< min(offset + maxChunk, inner.count)])
            offset += chunk.count
            let last = offset >= inner.count
            let header = UInt8(truncatingIfNeeded: i + (last ? 0xC0 : 0x80))
            let frame = [0xFF, header, UInt8(chunk.count + 4)] + chunk
            out.append(frame + [checksum(frame)])
            i += 1
        }
        return out
    }

    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        UInt8(truncatingIfNeeded: bytes.reduce(0) { $0 + Int($1) })
    }

    // MARK: Decode

    /// Parses an inner payload (after reassembly) into a packet.
    static func parse(payload b: [UInt8], isReply: Bool) -> Packet? {
        guard b.count >= 4 else { return nil }
        var segments: [Segment] = []
        var i = 4
        while i + 2 < b.count {
            let len = Int(b[i + 2])
            let end = min(b.count, i + 3 + len)
            segments.append(Segment(type: b[i], value: Array(b[(i + 3) ..< end])))
            i += len + 3
        }
        return Packet(index: UInt16(b[0]) | UInt16(b[1]) << 8, command: b[2], isReply: isReply, segments: segments)
    }

    /// Reassembles frames from the device into packets (one connection at a time).
    struct Reader {
        private var buffer: [UInt8] = []

        /// Feeds one notification. Returns a packet once a whole one has arrived.
        mutating func feed(_ frame: [UInt8]) -> Packet? {
            guard frame.count >= 4, frame[0] == 0xFF else { return nil }
            let header = frame[1]
            let body = Array(frame[3 ..< frame.count - 1])   // drop sync, header, length, checksum
            let reply = header & 0x20 != 0
            if header & 0x80 == 0 {
                buffer = []
                return parse(payload: body, isReply: reply)
            }
            buffer += body
            guard header & 0x40 != 0 else { return nil }
            defer { buffer = [] }
            return parse(payload: buffer, isReply: reply)
        }
    }

    // MARK: Helpers

    static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    static func rgb24(_ rgb: Int) -> [UInt8] {
        [UInt8((rgb >> 16) & 0xFF), UInt8((rgb >> 8) & 0xFF), UInt8(rgb & 0xFF)]
    }

    static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }
}
