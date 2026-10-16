import SwiftUI

/// "Touch Language" — saved touches you can send with one tap. Each is a tap rhythm with a
/// name and a two-stop colour gradient (start → end), as in the original app. Tap Send to
/// play it on your partner's bracelet.
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
                                .foregroundStyle(Theme.accent)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.white.opacity(0.06)))
                        }
                    }
                    .padding(.top, 8)

                    if store.meanings.isEmpty {
                        Text("You can start adding touches to your Touch Language.")
                            .foregroundStyle(Theme.subtitle)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    ForEach(store.meanings) { meaning in
                        meaningCard(meaning)
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

    @ViewBuilder private func meaningCard(_ meaning: TouchMeaning) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "play.circle").foregroundStyle(Theme.subtitle)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(meaning.label).font(.headline).foregroundStyle(.white)
                        if meaning.isNew { newBadge }
                    }
                    TouchViz(pattern: meaning.pattern,
                             colorRGB: meaning.colorRGB, endColorRGB: meaning.endColorRGB)
                }
                Spacer()
                Button {
                    Task {
                        await model.sendTouch(pattern: meaning.pattern,
                                              colorRGB: meaning.colorRGB,
                                              endColorRGB: meaning.endColorRGB)
                    }
                    clearNew(meaning)
                } label: {
                    Text("Send").font(.headline.weight(.bold)).foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var newBadge: some View {
        Text("New")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.bgBottom)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.85)))
    }

    private func clearNew(_ meaning: TouchMeaning) {
        guard let i = store.meanings.firstIndex(where: { $0.id == meaning.id }), store.meanings[i].isNew else { return }
        store.meanings[i].isNew = false
    }
}

private struct AddMeaningView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (TouchMeaning) -> Void
    @State private var label = ""
    @State private var startColor = Color(rgbInt: 0xFF2E74)
    @State private var endColor = Color(rgbInt: 0xAEE63C)
    @State private var taps = 2

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. I love you", text: $label)
                        .onChange(of: label) { if $0.count > 20 { label = String($0.prefix(20)) } }
                }
                Section("Colour (start → end)") {
                    ColorPicker("Start colour", selection: $startColor)
                    ColorPicker("End colour", selection: $endColor)
                    TouchViz(pattern: Array(repeating: 220, count: max(0, taps - 1)),
                             colorRGB: startColor.rgbInt, endColorRGB: endColor.rgbInt)
                        .frame(height: 30)
                }
                Section("Rhythm") {
                    Stepper("Taps: \(taps)", value: $taps, in: 1...10)
                }
            }
            .navigationTitle("New touch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let pattern = Array(repeating: 220, count: max(0, taps - 1))
                        onSave(TouchMeaning(label: label.isEmpty ? "Touch" : label,
                                            emoji: "",
                                            colorRGB: startColor.rgbInt,
                                            endColorRGB: endColor.rgbInt,
                                            pattern: pattern, isNew: true))
                        dismiss()
                    }
                }
            }
        }
    }
}
