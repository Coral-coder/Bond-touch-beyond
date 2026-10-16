import SwiftUI

/// Send your heartbeat: one press reads your current heart rate (Apple Watch / Health) and
/// sends 10 seconds of it to your partner's bracelet, which beats in time and then stops.
struct HeartView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var heart: HeartRateService
    @State private var beatStart = Date()
    @State private var sentBPM: Int?

    private var partnerName: String { model.selectedPartner?.displayName ?? "your partner" }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            Button {
                Task {
                    sentBPM = await model.sendHeartbeat()
                }
            } label: {
                // Driven by the clock, not an implicit animation, so only the size pulses —
                // a repeating animation also animated the button's position into place.
                TimelineView(.animation(paused: !model.sendingHeartbeat)) { context in
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [Theme.pink, Color(rgbInt: 0x9E1748)],
                                                 center: .center, startRadius: 10, endRadius: 130))
                            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 2))
                            .shadow(color: Theme.pink.opacity(0.6), radius: model.sendingHeartbeat ? 30 : 14)
                        VStack(spacing: 4) {
                            Image(systemName: "heart.fill").font(.system(size: 54)).foregroundStyle(.white)
                            Text(model.sendingHeartbeat ? "\(sentBPM ?? heart.currentBPM ?? 0) BPM" : "Send my heartbeat")
                                .font(Theme.font(17, .heavy)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 230, height: 230)
                    .scaleEffect(model.sendingHeartbeat ? pulse(at: context.date) : 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.sendingHeartbeat || model.selectedPartner == nil)
            .accessibilityLabel("Send my heartbeat to \(partnerName)")
            .onChange(of: model.sendingHeartbeat) { on in if on { beatStart = Date() } }

            Text(model.sendingHeartbeat
                 ? "\(partnerName)'s bracelet is beating with your heart for 10 seconds."
                 : "Press to send 10 seconds of your heartbeat to \(partnerName).")
                .font(Theme.font(15)).foregroundStyle(Theme.subtitle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if !heart.available {
                Text("Heart rate needs an Apple Watch paired with this iPhone.")
                    .font(Theme.font(13)).foregroundStyle(Theme.subtitle).multilineTextAlignment(.center)
            }
            if !model.statusLine.isEmpty, !model.sendingHeartbeat,
               model.statusLine.contains("heart") || model.statusLine.contains("Heart") {
                Text(model.statusLine).font(Theme.font(13)).foregroundStyle(Theme.amber)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            if model.partnerHeartbeatActive {
                Label("\(partnerName)'s heartbeat is playing on your bracelet", systemImage: "waveform.path.ecg")
                    .font(Theme.font(13, .semibold)).foregroundStyle(Theme.pink)
            }
            Spacer()
        }
        .padding()
        .screenBackground()
    }

    /// A heartbeat-shaped size: a big "lub" swell, then a smaller "dub" swell, then rest —
    /// like a real heart.
    private func pulse(at date: Date) -> CGFloat {
        let phase = date.timeIntervalSince(beatStart).truncatingRemainder(dividingBy: beatInterval) / beatInterval
        func bump(_ start: Double, _ width: Double) -> Double {
            guard phase >= start, phase < start + width else { return 0 }
            return sin((phase - start) / width * .pi)
        }
        let lub = bump(0, 0.18) * 0.10
        let dub = bump(0.26, 0.15) * 0.05
        return 1 + CGFloat(lub + dub)
    }

    private var beatInterval: Double {
        guard let bpm = sentBPM ?? heart.currentBPM, bpm > 0 else { return 0.8 }
        return 60.0 / Double(bpm)
    }
}
