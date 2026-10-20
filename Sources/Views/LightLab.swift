import CoreBluetooth
import SwiftUI

/// Debug → Light lab: light the bracelet without vibrating, and play persistence-of-vision
/// tests — text or a shape as a run of columns flashed fast enough to see when the band is
/// swung. Built on what the firmware accepts (docs/FIRMWARE_LED_VIBE.md):
///  • Bond Touch / Touch 4 / Mini: the 0x33 LED test queue — up to 256 silent, firmware-timed
///    steps, each with its own colour for each of the three LEDs, at 5 ms or more per step.
///    A column is the three LEDs (top, middle, bottom — the order is a guess, so it can be
///    changed), so text uses a 3-pixel-tall font.
///  • Bond Touch More: no fast queue for its LEDs, so Morse (on/off) streamed from the phone.
struct LightLabView: View {
    @EnvironmentObject var model: AppModel
    @State private var color = Color(rgbInt: 0xEC5A89)
    @State private var brightness = 80.0
    @State private var mode = Mode.text
    @State private var text = "HI ♥"
    @State private var stepMs = 6.0
    @State private var morseUnit = 120.0
    @State private var repeats = 1
    @State private var order = Order.oneTwoThree
    @State private var batch = false
    @State private var previewStart: Date?
    @State private var note = ""

    enum Mode: String, CaseIterable, Identifiable {
        case text, heart, smile, wave, morse
        var id: String { rawValue }
        var title: String {
            switch self {
            case .text: return "Text"
            case .heart: return "Heart"
            case .smile: return "Smile"
            case .wave: return "Wave"
            case .morse: return "Morse"
            }
        }
    }

    /// Which LED shows the top, middle and bottom row.
    enum Order: String, CaseIterable, Identifiable {
        case oneTwoThree = "1-2-3", threeTwoOne = "3-2-1", twoOneThree = "2-1-3", oneThreeTwo = "1-3-2"
        var id: String { rawValue }
        var leds: [Int] { rawValue.split(separator: "-").map { Int($0)! - 1 } }
    }

    private var gen: BondGeneration? { model.bracelet.generation }
    private var queueModel: Bool { gen == .v2 || gen == .v4 || gen == .mini }
    private var minStep: Double { gen == .v4 || gen == .mini ? 4 : 5 }

    var body: some View {
        Form {
            Section {
                Text(braceletLine).font(.footnote)
            }
            Section("Colour") {
                ColorPicker("Colour", selection: $color, supportsOpacity: false)
                HStack {
                    Text("Brightness")
                    Slider(value: $brightness, in: 1...100, step: 1)
                    Text("\(Int(brightness))").monospacedDigit().frame(width: 34)
                }
                Button("Light only — no vibration (1 s)") { lightOnly() }
                    .disabled(gen == nil || gen == .v1)
                Button("Rainbow wave") { model.feel(model.rainbowWaveTouch()) }
                    .disabled(gen == nil || gen == .v1)
            }
            Section {
                Picker("Pattern", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                if mode == .text || mode == .morse {
                    TextField("Text", text: $text).textInputAutocapitalization(.characters)
                }
                if mode == .morse {
                    Stepper("Dot: \(Int(morseUnit)) ms", value: $morseUnit, in: 40...400, step: 10)
                } else {
                    Stepper("Column: \(Int(stepMs)) ms", value: $stepMs, in: minStep...100, step: 1)
                    Picker("LED order (top → bottom)", selection: $order) {
                        ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Stepper("Repeat × \(repeats)", value: $repeats, in: 1...20)
                if gen == .v4 || gen == .mini {
                    Toggle("Batch writes (0x88, experimental)", isOn: $batch)
                }
                preview
                Text(summary).font(.caption).foregroundStyle(.secondary)
                Button("Play on the bracelet") { play() }
                    .disabled(gen == nil || gen == .v1 || (mode != .morse && !queueModel))
                Button("Preview here") { previewStart = Date() }
            } header: { Text("Persistence of vision") } footer: {
                Text("Swing the band quickly in a dark room. Columns run left to right; text is 3 pixels tall (one per LED). Step times under 5 ms reboot a Bond Touch, so they aren't offered. On a Bond Touch More only Morse works (its LEDs have no fast queue).")
            }
            if !note.isEmpty {
                Section { Text(note).font(.footnote) }
            }
        }
        .navigationTitle("Light lab")
    }

    private var braceletLine: String {
        switch gen {
        case nil: return "No bracelet connected."
        case .v1?: return "Classic Bond Touch: not supported here."
        case .v3?: return "Bond Touch More: light-only and Morse."
        case .v2?: return "Bond Touch: light-only, POV queue (≥ 5 ms columns)."
        case .v4?: return "Bond Touch 4: light-only, POV queue (≥ 4 ms columns)."
        case .mini?: return "Bond Mini: light-only, POV queue (≥ 4 ms columns)."
        default: return "Bracelet connected."
        }
    }

    // MARK: Building the pattern

    /// The pattern as steps: three LED colours (top, middle, bottom rows) and a duration.
    private var steps: [(colors: [Int], ms: Int)] {
        let rgb = color.rgbInt
        if mode == .morse {
            let on = Morse.timeline(text, unit: Int(morseUnit))
            var out: [(colors: [Int], ms: Int)] = []
            for (i, ms) in on.enumerated() { out.append((i % 2 == 0 ? [rgb, rgb, rgb] : [0, 0, 0], ms)) }
            return Array(repeating: out + [([0, 0, 0], Int(morseUnit) * 7)], count: repeats).flatMap { $0 }
        }
        let columns = bitmap
        let map = order.leds
        let one = columns.map { col -> (colors: [Int], ms: Int) in
            var leds = [0, 0, 0]
            for row in 0..<3 where col[row] { leds[map[row]] = rgb }
            return (leds, Int(stepMs))
        }
        // A dark gap between repeats.
        let gap = Array(repeating: (colors: [0, 0, 0], ms: Int(stepMs)), count: 3)
        return Array((0..<repeats).map { _ in one + gap }.joined())
    }

    /// Columns of three pixels (top, middle, bottom).
    private var bitmap: [[Bool]] {
        switch mode {
        case .text: return TinyFont.columns(text)
        case .heart: return TinyFont.columns("♥")
        case .smile: return TinyFont.rows([".#...#.", "#.....#", ".#####."])
        case .wave: return TinyFont.rows(["#...#...#...", ".#.#.#.#.#.#", "..#...#...#."])
        case .morse: return []
        }
    }

    private var summary: String {
        let s = steps
        let total = s.reduce(0) { $0 + $1.ms }
        var line = "\(s.count) steps, \(String(format: "%.2f", Double(total) / 1000)) s"
        if mode != .morse, s.count > 256 { line += " — only the first 256 fit the queue" }
        return line
    }

    // MARK: Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The whole picture, as it would appear in the air.
            if mode != .morse {
                Canvas { ctx, size in
                    let cols = bitmap
                    guard !cols.isEmpty else { return }
                    let cell = min(size.height / 3, size.width / CGFloat(cols.count))
                    for (x, col) in cols.enumerated() {
                        for row in 0..<3 where col[row] {
                            let r = CGRect(x: CGFloat(x) * cell, y: CGFloat(row) * cell, width: cell * 0.85, height: cell * 0.85)
                            ctx.fill(Path(ellipseIn: r), with: .color(color))
                        }
                    }
                }
                .frame(height: 36)
            }
            // The three LEDs, playing it in time.
            TimelineView(.animation(paused: previewStart == nil)) { tl in
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { led in
                        Circle().fill(Color(rgbInt: ledColor(led, at: tl.date))).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.secondary.opacity(0.4)))
                    }
                    Text("LED 1 · 2 · 3").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// LED `led`'s colour at `date` in the preview (slowed 20× so it can be seen).
    private func ledColor(_ led: Int, at date: Date) -> Int {
        guard let start = previewStart else { return 0x202020 }
        var t = date.timeIntervalSince(start) * 1000 / (mode == .morse ? 1 : 20)
        for s in steps {
            if t < Double(s.ms) { return s.colors[led] == 0 ? 0x202020 : s.colors[led] }
            t -= Double(s.ms)
        }
        DispatchQueue.main.async { previewStart = nil }
        return 0x202020
    }

    // MARK: Sending

    private func lightOnly() {
        guard let gen else { return }
        model.bracelet.send(BondGATT.lightOnly(gen, rgb: color.rgbInt, brightness: UInt8(brightness), ms: 1000))
        if gen == .v3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { model.bracelet.send([BondGATT.v3LightOff]) }
        }
        note = "Sent: light only, \(Int(brightness))% for 1 s."
    }

    private func play() {
        guard let gen else { return }
        let s = steps
        if gen == .v3 {
            // Streamed from the phone: colour on / clear at each change.
            var at = 0.0
            for step in s {
                let lit = step.colors.contains { $0 != 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                    model.bracelet.send([lit ? BondGATT.v3Color(color.rgbInt) : BondGATT.v3LightOff])
                }
                at += Double(step.ms) / 1000
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { model.bracelet.send([BondGATT.v3LightOff]) }
            note = "Streaming \(s.count) changes over \(String(format: "%.1f", at)) s."
            return
        }
        guard queueModel else { return }
        let frames = s.prefix(256).map { BondGATT.lightStep($0.colors, brightness: UInt8(brightness), ms: $0.ms) }
        let writes = (batch && (gen == .v4 || gen == .mini)) ? BondGATT.batched(Array(frames)) : Array(frames)
        model.bracelet.send(writes + [BondGATT.lightQueueStart])
        note = "Loaded \(frames.count) steps\(batch ? " in \(writes.count) batched writes" : ""), then started the queue."
    }
}

/// A 3-pixel-tall font (one pixel per LED), drawn as rows of `#` and `.`.
enum TinyFont {
    static let glyphs: [Character: [String]] = [
        "A": [".#.", "###", "#.#"], "B": ["#..", "###", "###"], "C": ["###", "#..", "###"],
        "D": ["##.", "#.#", "##."], "E": ["###", "##.", "###"], "F": ["###", "##.", "#.."],
        "G": ["##.", "#.#", "###"], "H": ["#.#", "###", "#.#"], "I": ["###", ".#.", "###"],
        "J": ["..#", "#.#", "###"], "K": ["#.#", "##.", "#.#"], "L": ["#..", "#..", "###"],
        "M": ["#...#", "##.##", "#.#.#"], "N": ["#..#", "##.#", "#.##"], "O": ["###", "#.#", "###"],
        "P": ["###", "###", "#.."], "Q": ["###", "###", "..#"], "R": ["##.", "##.", "#.#"],
        "S": [".##", ".#.", "##."], "T": ["###", ".#.", ".#."], "U": ["#.#", "#.#", "###"],
        "V": ["#.#", "#.#", ".#."], "W": ["#.#.#", "#.#.#", ".#.#."], "X": ["#.#", ".#.", "#.#"],
        "Y": ["#.#", ".#.", ".#."], "Z": ["##.", ".#.", ".##"],
        "0": ["###", "#.#", "###"], "1": ["##.", ".#.", "###"], "2": ["##.", ".#.", ".##"],
        "3": ["###", ".##", "###"], "4": ["#.#", "###", "..#"], "5": [".##", ".#.", "##."],
        "6": ["#..", "###", "###"], "7": ["###", "..#", "..#"], "8": ["###", "###", "###"],
        "9": ["###", "###", "..#"], " ": ["..", "..", ".."], "!": ["#", "#", "."], ".": [".", ".", "#"],
        "-": ["..", "##", ".."], "+": [".#.", "###", ".#."], "?": ["##.", ".#.", ".#."],
        "♥": ["##.##", "#####", ".###."], "❤": ["##.##", "#####", ".###."],
    ]

    /// `text` as columns, a blank column between letters.
    static func columns(_ text: String) -> [[Bool]] {
        var out: [[Bool]] = []
        for ch in text.uppercased() {
            guard let g = glyphs[ch] ?? glyphs[Character(String(ch).replacingOccurrences(of: "\u{FE0F}", with: ""))] else { continue }
            if !out.isEmpty { out.append([false, false, false]) }
            out += rows(g)
        }
        return out
    }

    /// Three row strings → columns.
    static func rows(_ r: [String]) -> [[Bool]] {
        let rows = r.map(Array.init)
        let width = rows.map(\.count).max() ?? 0
        return (0..<width).map { x in (0..<3).map { y in y < rows.count && x < rows[y].count && rows[y][x] == "#" } }
    }
}

/// International Morse: text as on/off milliseconds (dot = 1 unit, dash = 3, gaps 1 / 3 / 7).
enum Morse {
    static let codes: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....",
        "I": "..", "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.",
        "Q": "--.-", "R": ".-.", "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
        "Y": "-.--", "Z": "--..", "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
    ]

    /// Alternating on, off, on… durations, starting with on.
    static func timeline(_ text: String, unit: Int) -> [Int] {
        var segments: [(on: Bool, units: Int)] = []
        func add(_ on: Bool, _ units: Int) {
            if !on, segments.isEmpty { return }                     // no leading gap
            if let last = segments.last, last.on == on {
                segments[segments.count - 1].units = on ? last.units + units : max(last.units, units)
            } else {
                segments.append((on, units))
            }
        }
        for word in text.uppercased().split(separator: " ") {
            add(false, 7)
            for ch in word {
                guard let code = codes[ch] else { continue }
                add(false, 3)
                for sym in code {
                    add(false, 1)
                    add(true, sym == "-" ? 3 : 1)
                }
            }
        }
        if segments.last?.on == false { segments.removeLast() }
        return segments.map { $0.units * unit }
    }
}
