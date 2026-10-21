import SwiftUI

/// Debug → Light lab: light the bracelet without vibrating (docs/FIRMWARE_LED_VIBE.md) — a
/// 0x26 frame at motor strength 0 on a Bond Touch / Touch 4 / Mini, FFB1 0x4B on a Bond Touch
/// More (cleared after). Pattern and text experiments are parked until the band's firmware
/// can show them well.
struct LightLabView: View {
    @EnvironmentObject var model: AppModel
    @State private var color = Color(rgbInt: 0xEC5A89)
    @State private var brightness = 80.0
    @State private var seconds = 1.0
    @State private var note = ""

    private var gen: BondGeneration? { model.bracelet.generation }

    var body: some View {
        Form {
            Section {
                Text(braceletLine).font(.footnote)
            }
            Section {
                ColorPicker("Colour", selection: $color, supportsOpacity: false)
                HStack {
                    Text("Brightness")
                    Slider(value: $brightness, in: 1...100, step: 1)
                    Text("\(Int(brightness))").monospacedDigit().frame(width: 34)
                }
                Stepper("For \(Int(seconds)) s", value: $seconds, in: 1...10, step: 1)
                Button("Light it — no vibration") { lightOnly() }
                    .disabled(gen == nil || gen == .v1)
            } header: { Text("Light without vibrating") }
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
        default: return "Bracelet connected."
        }
    }

    private func lightOnly() {
        guard let gen else { return }
        let ms = UInt16(seconds * 1000)
        model.bracelet.send(BondGATT.lightOnly(gen, rgb: color.rgbInt, brightness: UInt8(brightness), ms: ms))
        if gen == .v3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { model.bracelet.send([BondGATT.v3LightOff]) }
        }
        note = "Sent: light only, \(Int(brightness))% for \(Int(seconds)) s."
    }
}
