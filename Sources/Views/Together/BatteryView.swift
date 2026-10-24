import SwiftUI

/// Your personal battery and how you're feeling. The battery comes from Apple Health (heart-
/// rate variability against your usual, resting heart rate, last night's sleep) and the energy
/// you log. Partners see it quietly; they're only notified when you're stressed or overwhelmed.
struct BatteryView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var battery: BatteryService
    @AppStorage("shareMood") private var share = true
    @State private var picked: Int?
    @State private var energy = 60.0
    @State private var note = ""
    @State private var logged = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                myBattery
                StressChart(battery: battery)
                EveryoneHRV(model: model, battery: battery)
                logCard
                partnersCard
                historyCard
                Toggle(isOn: $share) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share with my partners").foregroundStyle(Theme.title)
                        Text("They see your battery and mood quietly — a notification only when you're stressed or overwhelmed. Notes stay on this phone.")
                            .font(.caption).foregroundStyle(Theme.subtitle)
                    }
                }
                .tint(Theme.accent).padding(16).glass(cornerRadius: Theme.cardCorner)
            }
            .padding(16)
        }
        .navigationTitle("Stress & mood")
        .task { await battery.refresh() }
    }

    private var myBattery: some View {
        let level = battery.battery
        let face = level.map { Stress.face(100 - $0) }
        return VStack(spacing: 8) {
            Text(face?.emoji ?? "🫥").font(.system(size: 84))
            Text(face?.label ?? "—").font(Theme.font(28, .heavy)).foregroundStyle(Theme.title)
            Text(level.map { "Stress \(100 - $0) / 100 · energy \($0)%" } ?? "").font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
            Text(levelText(level)).font(Theme.font(14, .semibold)).foregroundStyle(Theme.subtitle)
            HStack(spacing: 14) {
                stat("HRV", battery.hrv.map { "\(Int($0)) ms" }, battery.hrvBaseline.map { "usual \(Int($0))" })
                stat("Resting HR", battery.restingHR.map { "\(Int($0))" }, "bpm")
                stat("Sleep", battery.sleepHours.map { String(format: "%.1f h", $0) }, "last night")
            }
        }
        .frame(maxWidth: .infinity).padding(18).glass(cornerRadius: Theme.cardCorner)
    }

    private func stat(_ title: String, _ value: String?, _ sub: String?) -> some View {
        VStack(spacing: 2) {
            Text(title).font(Theme.font(11, .bold)).foregroundStyle(Theme.subtitle)
            Text(value ?? "—").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            Text(sub ?? " ").font(Theme.font(10)).foregroundStyle(Theme.subtitle)
        }
        .frame(maxWidth: .infinity)
    }

    private func levelText(_ l: Int?) -> String {
        guard let l else { return "Log how you feel, or allow Health access, to see your stress" }
        switch l {
        case ..<20: return "Running on empty — go gently"
        case ..<45: return "Low — take it easy"
        case ..<70: return "Doing OK"
        default: return "Charged up"
        }
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How are you feeling?").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Moods.all.indices, id: \.self) { i in
                    let m = Moods.all[i]
                    Button { picked = i; UISelectionFeedbackGenerator().selectionChanged() } label: {
                        VStack(spacing: 2) {
                            Text(m.emoji).font(.system(size: 26))
                            Text(m.label).font(Theme.font(10, .bold)).foregroundStyle(Theme.title).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 14).fill(picked == i ? Theme.accent.opacity(0.3) : Theme.ink.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(picked == i ? Theme.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text("Energy").font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                Slider(value: $energy, in: 0...100).tint(Theme.accent)
                Text("\(Int(energy))%").font(Theme.font(13, .bold)).monospacedDigit().foregroundStyle(Theme.subtitle)
            }
            TextField("A note just for you (optional)", text: $note)
                .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.opacity(0.06)))
            Button(logged ? "Logged ✓" : "Log it") { log() }
                .buttonStyle(AccentButtonStyle(height: 46)).disabled(picked == nil)
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private func log() {
        guard let i = picked else { return }
        let m = Moods.all[i]
        let entry = MoodEntry(emoji: m.emoji, label: m.label, level: m.level, energy: Int(energy), note: note,
                              battery: battery.bodyBattery.map { ($0 + Int(energy)) / 2 } ?? Int(energy))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await model.logMood(entry) }
        note = ""; logged = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { logged = false }
    }

    private var partnersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your people").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
            ForEach(model.partners) { p in PartnerMoodRow(partner: p) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
    }

    @ViewBuilder private var historyCard: some View {
        if !battery.entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your log").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                ForEach(battery.entries.suffix(12).reversed()) { e in
                    HStack(spacing: 10) {
                        Text(e.emoji).font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(e.label) · \(e.energy)% energy").font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                            if !e.note.isEmpty { Text(e.note).font(Theme.font(12)).foregroundStyle(Theme.subtitle).lineLimit(2) }
                        }
                        Spacer()
                        Text(e.at.formatted(.relative(presentation: .named))).font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
        }
    }
}

/// A partner's battery and mood, as they share it.
struct PartnerMoodRow: View {
    let partner: Partner
    var body: some View {
        HStack(spacing: 12) {
            PartnerFace(partner: partner, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(partner.displayName).font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                if let m = partner.presence?.mood {
                    Text("\(m.emoji) \(m.label) · \(m.at.formatted(.relative(presentation: .named)))")
                        .font(Theme.font(12, .semibold)).foregroundStyle(m.needsCare ? Theme.amber : Theme.subtitle)
                } else {
                    Text("Not sharing yet").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                }
            }
            Spacer()
            if let m = partner.presence?.mood {
                VStack(spacing: 0) {
                    Text(Stress.face(m.stress).emoji).font(.system(size: 30))
                    Text(Stress.face(m.stress).label).font(Theme.font(9, .bold)).foregroundStyle(Theme.subtitle)
                }
            }
        }
    }
}

/// A battery icon filled to `level`, green → amber → red.
struct BatteryGauge: View {
    let level: Int?
    var size: CGFloat = 60
    var body: some View {
        let l = Double(level ?? 0) / 100
        let color: Color = level == nil ? Theme.subtitle : l < 0.2 ? Theme.danger : l < 0.45 ? Theme.amber : Theme.lime
        HStack(spacing: size * 0.03) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: size * 0.12).stroke(Theme.title.opacity(0.7), lineWidth: max(1.5, size * 0.04))
                RoundedRectangle(cornerRadius: size * 0.08).fill(color)
                    .frame(width: max(0, (size * 1.1 - size * 0.12) * l))
                    .padding(size * 0.06)
            }
            .frame(width: size * 1.1, height: size * 0.55)
            RoundedRectangle(cornerRadius: size * 0.04).fill(Theme.title.opacity(0.7)).frame(width: size * 0.07, height: size * 0.22)
        }
        .accessibilityLabel(level.map { "Battery \($0) percent" } ?? "Battery unknown")
    }
}
