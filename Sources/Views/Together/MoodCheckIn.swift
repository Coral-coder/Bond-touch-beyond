import SwiftUI

/// A quick mood check-in from Home: pick how you feel, set your energy, send. It's logged and
/// shared with your partners just like a log from Stress & mood (quietly — they're only
/// notified when you're stressed or overwhelmed).
struct MoodCheckInSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Int?
    @State private var energy = 60.0
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("How are you feeling?").font(Theme.font(22, .heavy)).foregroundStyle(Theme.title)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(Moods.all.indices, id: \.self) { i in
                            let m = Moods.all[i]
                            Button { picked = i; UISelectionFeedbackGenerator().selectionChanged() } label: {
                                VStack(spacing: 2) {
                                    Text(m.emoji).font(.system(size: 30))
                                    Text(m.label).font(Theme.font(10, .bold)).foregroundStyle(Theme.title)
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 14).fill(picked == i ? Theme.accent.opacity(0.3) : Theme.ink.opacity(0.06)))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(picked == i ? Theme.accent : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(m.label)
                            .accessibilityAddTraits(picked == i ? .isSelected : [])
                        }
                    }
                    HStack {
                        Text("Energy").font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                        Slider(value: $energy, in: 0...100).tint(Theme.accent)
                        Text("\(Int(energy))%").font(Theme.font(13, .bold)).monospacedDigit().foregroundStyle(Theme.subtitle)
                    }
                    Button(sent ? "Sent" : "Send my mood") { send() }
                        .buttonStyle(AccentButtonStyle(height: 50))
                        .disabled(picked == nil || sent)
                    Text(model.partners.isEmpty
                         ? "It's saved in Stress & mood."
                         : "Your partners see it quietly; they're only notified if you're stressed or overwhelmed.")
                        .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                }
                .padding(20)
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        guard let i = picked else { return }
        let m = Moods.all[i]
        let body = model.battery.bodyBattery
        let entry = MoodEntry(emoji: m.emoji, label: m.label, level: m.level, energy: Int(energy), note: "",
                              battery: body.map { ($0 + Int(energy)) / 2 } ?? Int(energy))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        sent = true
        Task {
            await model.logMood(entry)
            try? await Task.sleep(nanoseconds: 600_000_000)
            dismiss()
        }
    }
}
