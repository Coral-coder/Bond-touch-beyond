import SwiftUI

/// "Touch Language" — saved touches you can send with one tap. Each is a glowing stroke
/// pattern with a label; tap Send to play it on your partner's bracelet.
struct MeaningsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(); PartnerBar(); Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Touch Language")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.teal)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.white.opacity(0.06)))
                        }
                    }
                    .padding(.top, 8)

                    ForEach(store.meanings) { meaning in
                        GlassCard {
                            HStack(spacing: 12) {
                                Image(systemName: "play.circle")
                                    .foregroundStyle(Theme.subtitle)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(meaning.emoji)  \(meaning.label)")
                                        .font(.headline).foregroundStyle(.white)
                                    TouchViz(pattern: meaning.pattern, colorRGB: meaning.colorRGB)
                                }
                                Spacer()
                                Button {
                                    Task { await model.sendTouch(pattern: meaning.pattern, colorRGB: meaning.colorRGB) }
                                } label: {
                                    Text("Send").font(.headline.weight(.bold)).foregroundStyle(Theme.teal)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddMeaningView { store.meanings.append($0) }
        }
    }
}

private struct AddMeaningView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (TouchMeaning) -> Void
    @State private var label = ""
    @State private var emoji = "💜"
    @State private var color: Color = .pink
    @State private var taps = 2

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label", text: $label)
                TextField("Emoji", text: $emoji)
                ColorPicker("Colour", selection: $color)
                Stepper("Taps: \(taps)", value: $taps, in: 1...10)
            }
            .navigationTitle("New touch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let pattern = Array(repeating: 220, count: max(0, taps - 1))
                        onSave(TouchMeaning(label: label.isEmpty ? "Touch" : label,
                                            emoji: emoji.isEmpty ? "💜" : emoji,
                                            colorRGB: color.rgbInt, pattern: pattern))
                        dismiss()
                    }
                }
            }
        }
    }
}
