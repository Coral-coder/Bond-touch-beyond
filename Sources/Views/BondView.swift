import SwiftUI

/// The main screen once paired: tap to send a touch, and see touches received.
struct BondView: View {
    @EnvironmentObject var model: AppModel
    @State private var taps: [Date] = []
    @State private var color: Color = .pink

    var body: some View {
        VStack(spacing: 20) {
            braceletStatus

            Text("Tap the heart in a rhythm, then Send. Your partner's bracelet plays it back.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                taps.append(Date())
            } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(color)
                    .scaleEffect(taps.isEmpty ? 1 : 1.08)
                    .animation(.spring(duration: 0.2), value: taps.count)
            }
            .buttonStyle(.plain)

            Text("\(taps.count) tap\(taps.count == 1 ? "" : "s")")
                .monospacedDigit()

            ColorPicker("Glow colour", selection: $color)
                .padding(.horizontal, 40)

            HStack {
                Button("Clear") { taps.removeAll() }
                    .buttonStyle(.bordered)
                    .disabled(taps.isEmpty)
                Button("Send touch") {
                    Task {
                        await model.sendTouch(pattern: patternMillis(from: taps), colorRGB: color.rgbInt)
                        taps.removeAll()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(taps.isEmpty)
            }

            if !model.incoming.isEmpty {
                List(model.incoming.reversed()) { touch in
                    HStack {
                        Circle().fill(Color(rgbInt: touch.colorRGB)).frame(width: 18, height: 18)
                        Text("\(touch.pattern.count + 1) taps")
                        Spacer()
                        Text(touch.sentAt, style: .time).foregroundStyle(.secondary)
                    }
                }
                .frame(maxHeight: 180)
            }
            Spacer()
        }
        .padding()
    }

    private var braceletStatus: some View {
        let (text, systemImage, tint): (String, String, Color) = {
            switch model.braceletState {
            case .connected: return ("Bracelet connected", "antenna.radiowaves.left.and.right", .green)
            case .scanning, .connecting: return ("Looking for bracelet…", "dot.radiowaves.left.and.right", .orange)
            case .bluetoothOff: return ("Bluetooth off", "antenna.radiowaves.left.and.right.slash", .red)
            case .unsupportedUntilProtocolResolved:
                return ("Bracelet link pending protocol", "wrench.and.screwdriver", .gray)
            case .disconnected: return ("Bracelet not connected", "antenna.radiowaves.left.and.right.slash", .gray)
            }
        }()
        return Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(tint)
    }

    /// Converts tap timestamps into inter-tap gaps in milliseconds.
    private func patternMillis(from taps: [Date]) -> [Int] {
        guard taps.count > 1 else { return [] }
        return zip(taps.dropFirst(), taps).map { Int($0.timeIntervalSince($1) * 1000) }
    }
}
