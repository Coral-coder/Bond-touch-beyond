import CoreBluetooth
import SwiftUI

/// Debug → Light lab: light the bracelet without vibrating, and play persistence-of-vision
/// tests — text or a shape as a run of columns flashed fast enough to see when the band is
/// swung. Built on what the firmware accepts (docs/FIRMWARE_LED_VIBE.md):
///  • Bond Touch / Touch 4 / Mini: the 0x33 LED test queue — up to 256 silent, firmware-timed
///    steps, each with its own colour for each of the three LEDs, at 5 ms or more per step.
///    A column is the three LEDs (top, middle, bottom — the order is a guess, so it can be
///    changed), so text uses a 3-pixel-tall font.
///  • Bond Touch More: 9 bar LEDs, so text uses a 9-pixel-tall font (a 5×7 font centred or
///    stretched to 9). Each column plays as touch samples — a sample lights one LED or a run
///    of neighbouring LEDs, 50 ms each — with the motor optionally set to 0 meanwhile.
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
    /// Bond Touch More: letters stretched from 7 to all 9 LEDs (else centred, 7 tall).
    @State private var stretch = true
    /// Bond Touch More: the bar's position 0 is the top row (else the bottom).
    @State private var flip = false
    /// Bond Touch More: vibration level 0 while it plays (experimental), then back.
    @State private var silent = true

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
    /// Pixels per column: the Bond Touch More's 9 bar LEDs, else 3 LEDs.
    private var tall: Bool { gen == .v3 || gen == nil }
    private var rowCount: Int { tall ? 9 : 3 }

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
                } else if tall {
                    Toggle("Letters 9 tall (stretched)", isOn: $stretch)
                    Toggle("Flip top and bottom", isOn: $flip)
                    Toggle("No vibration while it plays (experimental)", isOn: $silent)
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
                    .disabled(gen == nil || gen == .v1)
                Button("Preview here") { previewStart = Date() }
            } header: { Text("Persistence of vision") } footer: {
                Text(tall
                     ? "Bond Touch More: 9 pixels tall, one per bar LED. Each run of lit LEDs in a column is one 50 ms touch sample, so it's slow — swing slowly, or watch it scroll. Columns run left to right."
                     : "Swing the band quickly in a dark room. Columns run left to right; text is 3 pixels tall (one per LED). Step times under 5 ms reboot a Bond Touch, so they aren't offered.")
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

    /// Columns of pixels, top first: 9 on a Bond Touch More, else 3.
    private var bitmap: [[Bool]] {
        if tall {
            switch mode {
            case .text: return TallFont.columns(text, stretch: stretch)
            case .heart: return TallFont.rows(TallFont.heart)
            case .smile: return TallFont.rows(TallFont.smile)
            case .wave: return TallFont.rows(TallFont.wave)
            case .morse: return []
            }
        }
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
        if tall, mode != .morse {
            let n = barSamples.count
            return "\(bitmap.count) columns → \(n) samples, \(String(format: "%.1f", Double(n) * 0.05)) s"
        }
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
                    let rows = cols[0].count
                    let cell = min(size.height / CGFloat(rows), size.width / CGFloat(cols.count))
                    for (x, col) in cols.enumerated() {
                        for row in 0..<rows where col[row] {
                            let r = CGRect(x: CGFloat(x) * cell, y: CGFloat(row) * cell, width: cell * 0.85, height: cell * 0.85)
                            ctx.fill(Path(ellipseIn: r), with: .color(color))
                        }
                    }
                }
                .frame(height: tall ? 72 : 36)
            }
            // The three LEDs, playing it in time.
            if !tall { TimelineView(.animation(paused: previewStart == nil)) { tl in
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { led in
                        Circle().fill(Color(rgbInt: ledColor(led, at: tl.date))).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.secondary.opacity(0.4)))
                    }
                    Text("LED 1 · 2 · 3").font(.caption2).foregroundStyle(.secondary)
                }
            } }
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

    /// Bond Touch More: the picture as touch samples — per column, a sample per piece of up to
    /// 3 neighbouring lit LEDs, a blank sample for an empty column, and a blank between
    /// repeats. Each lit LED also gets a dim halo on its neighbours (the firmware's own).
    private var barSamples: [Int] {
        var out: [Int] = []
        for _ in 0..<repeats {
            for col in bitmap {
                // Row 0 is the top: the bar's top is position 8 unless flipped.
                let lit = col.indices.filter { col[$0] }.map { flip ? $0 : 8 - $0 }.sorted()
                var runs: [(Int, Int)] = []
                for p in lit {
                    if let last = runs.last, last.1 == p - 1 { runs[runs.count - 1].1 = p } else { runs.append((p, p)) }
                }
                if runs.isEmpty { out.append(TouchPattern.none) }
                // A sample lights one LED, or two ends with only the middle one between them
                // (wider spans leave the middle dark — docs/FIRMWARE_LED_VIBE.md §12), so a
                // run is played in pieces of at most 3.
                for r in runs {
                    var lo = r.0
                    while lo <= r.1 {
                        let hi = min(r.1, lo + 2)
                        out.append(TouchPattern.sample(lo == hi ? [lo] : [lo, hi]))
                        lo = hi + 1
                    }
                }
            }
            out += Array(repeating: TouchPattern.none, count: 4)
        }
        return out
    }

    private func play() {
        guard let gen else { return }
        let s = steps
        if gen == .v3, mode != .morse {
            if silent { model.bracelet.silenceMotor(true) }
            let seconds = model.bracelet.playSamples(barSamples, rgb: color.rgbInt)
            if silent {
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.5) { model.bracelet.silenceMotor(false) }
            }
            note = "Playing \(barSamples.count) samples over \(String(format: "%.1f", seconds)) s\(silent ? ", vibration at 0 meanwhile" : "")."
            return
        }
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

/// A 9-pixel-tall font for the Bond Touch More's 9 bar LEDs: the classic 5×7 LCD font,
/// centred (rows 1…7) or stretched to all 9 rows, plus shapes drawn at the full 9.
enum TallFont {
    /// 5 columns per glyph; bit 0 is the top row.
    static let glyphs: [Character: [UInt8]] = [
        " ": [0x00, 0x00, 0x00], "!": [0x00, 0x5F, 0x00], "?": [0x02, 0x01, 0x51, 0x09, 0x06],
        ".": [0x60, 0x60], ",": [0x80, 0x60], "-": [0x08, 0x08, 0x08, 0x08], "+": [0x08, 0x08, 0x3E, 0x08, 0x08],
        ":": [0x36, 0x36], "'": [0x07], "/": [0x20, 0x10, 0x08, 0x04, 0x02],
        "0": [0x3E, 0x51, 0x49, 0x45, 0x3E], "1": [0x00, 0x42, 0x7F, 0x40, 0x00], "2": [0x72, 0x49, 0x49, 0x49, 0x46],
        "3": [0x21, 0x41, 0x49, 0x4D, 0x33], "4": [0x18, 0x14, 0x12, 0x7F, 0x10], "5": [0x27, 0x45, 0x45, 0x45, 0x39],
        "6": [0x3C, 0x4A, 0x49, 0x49, 0x31], "7": [0x41, 0x21, 0x11, 0x09, 0x07], "8": [0x36, 0x49, 0x49, 0x49, 0x36],
        "9": [0x46, 0x49, 0x49, 0x29, 0x1E],
        "A": [0x7C, 0x12, 0x11, 0x12, 0x7C], "B": [0x7F, 0x49, 0x49, 0x49, 0x36], "C": [0x3E, 0x41, 0x41, 0x41, 0x22],
        "D": [0x7F, 0x41, 0x41, 0x41, 0x3E], "E": [0x7F, 0x49, 0x49, 0x49, 0x41], "F": [0x7F, 0x09, 0x09, 0x09, 0x01],
        "G": [0x3E, 0x41, 0x41, 0x51, 0x73], "H": [0x7F, 0x08, 0x08, 0x08, 0x7F], "I": [0x00, 0x41, 0x7F, 0x41, 0x00],
        "J": [0x20, 0x40, 0x41, 0x3F, 0x01], "K": [0x7F, 0x08, 0x14, 0x22, 0x41], "L": [0x7F, 0x40, 0x40, 0x40, 0x40],
        "M": [0x7F, 0x02, 0x1C, 0x02, 0x7F], "N": [0x7F, 0x04, 0x08, 0x10, 0x7F], "O": [0x3E, 0x41, 0x41, 0x41, 0x3E],
        "P": [0x7F, 0x09, 0x09, 0x09, 0x06], "Q": [0x3E, 0x41, 0x51, 0x21, 0x5E], "R": [0x7F, 0x09, 0x19, 0x29, 0x46],
        "S": [0x26, 0x49, 0x49, 0x49, 0x32], "T": [0x03, 0x01, 0x7F, 0x01, 0x03], "U": [0x3F, 0x40, 0x40, 0x40, 0x3F],
        "V": [0x1F, 0x20, 0x40, 0x20, 0x1F], "W": [0x3F, 0x40, 0x38, 0x40, 0x3F], "X": [0x63, 0x14, 0x08, 0x14, 0x63],
        "Y": [0x03, 0x04, 0x78, 0x04, 0x03], "Z": [0x61, 0x59, 0x49, 0x4D, 0x43],
        "♥": [0x0C, 0x1E, 0x3C, 0x1E, 0x0C], "❤": [0x0C, 0x1E, 0x3C, 0x1E, 0x0C],
    ]

    static let heart = [
        ".##...##.", "####.####", "#########", "#########", ".#######.",
        "..#####..", "...###...", "....#....", ".........",
    ]
    static let smile = [
        "..#####..", ".#.....#.", "#..#.#..#", "#.......#", "#.#...#.#",
        "#..###..#", ".#.....#.", "..#####..", ".........",
    ]
    static let wave = [
        "#.......#.......", ".#.....#.#.....#", "..#...#...#...#.", "...#.#.....#.#..", "....#.......#...",
        "................", "................", "................", "................",
    ]

    /// `text` as 9-pixel columns (top first), one blank column between letters.
    static func columns(_ text: String, stretch: Bool) -> [[Bool]] {
        // 7 font rows onto 9: stretched repeats rows 1 and 5; centred pads a row above and below.
        let map: [Int?] = stretch ? [0, 1, 1, 2, 3, 4, 5, 5, 6] : [nil, 0, 1, 2, 3, 4, 5, 6, nil]
        var out: [[Bool]] = []
        for ch in text.uppercased() {
            let key = Character(String(ch).replacingOccurrences(of: "\u{FE0F}", with: ""))
            guard let g = glyphs[key] else { continue }
            if !out.isEmpty { out.append(Array(repeating: false, count: 9)) }
            for byte in g {
                out.append(map.map { row in row.map { byte & (1 << $0) != 0 } ?? false })
            }
        }
        return out
    }

    /// Nine row strings (`#` lit) → columns.
    static func rows(_ r: [String]) -> [[Bool]] {
        let rows = r.map(Array.init)
        let width = rows.map(\.count).max() ?? 0
        return (0..<width).map { x in (0..<9).map { y in y < rows.count && x < rows[y].count && rows[y][x] == "#" } }
    }
}
