import SwiftUI

/// Share your live heart rate (from HealthKit / Apple Watch) to your partner's bracelet,
/// which beats in time with it.
struct HeartView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var heart: HeartRateService
    @State private var beat = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.red)
                    .scaleEffect(beat ? 1.12 : 0.92)
                    .animation(.easeInOut(duration: beatInterval).repeatForever(autoreverses: true), value: beat)
                VStack {
                    Text(heart.currentBPM.map(String.init) ?? "–")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("BPM").font(.caption).foregroundStyle(.white.opacity(0.85))
                }
            }
            .onAppear { beat = true }

            if !heart.available {
                Text("Heart rate needs an iPhone paired with an Apple Watch (or Health data).")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            Toggle(isOn: Binding(
                get: { model.sharingHeartbeat },
                set: { on in Task { on ? await model.startSharingHeartbeat() : model.stopSharingHeartbeat() } }
            )) {
                Label("Send my heartbeat to \(model.selectedPartner?.displayName ?? "partner")",
                      systemImage: "antenna.radiowaves.left.and.right")
            }
            .padding(.horizontal)
            .disabled(!heart.available)

            if model.partnerHeartbeatActive {
                Label("Your partner's heartbeat is playing on your bracelet",
                      systemImage: "waveform.path.ecg")
                    .font(.footnote).foregroundStyle(.pink).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    private var beatInterval: Double {
        guard let bpm = heart.currentBPM, bpm > 0 else { return 0.8 }
        return 60.0 / Double(bpm)
    }
}
