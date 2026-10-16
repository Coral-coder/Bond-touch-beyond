import SwiftUI

/// Saved touch meanings — tap one to send its pattern + colour instantly.
struct MeaningsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var showAdd = false

    var body: some View {
        List {
            ForEach(store.meanings) { meaning in
                Button {
                    Task { await model.sendTouch(pattern: meaning.pattern, colorRGB: meaning.colorRGB) }
                } label: {
                    HStack(spacing: 12) {
                        Text(meaning.emoji).font(.title2)
                        Circle().fill(Color(rgbInt: meaning.colorRGB)).frame(width: 16, height: 16)
                        Text(meaning.label)
                        Spacer()
                        Image(systemName: "paperplane.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { store.meanings.remove(atOffsets: $0) }
        }
        .toolbar {
            Button { showAdd = true } label: { Image(systemName: "plus") }
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
    @State private var color: Color = .purple
    @State private var taps = 2

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label", text: $label)
                TextField("Emoji", text: $emoji)
                ColorPicker("Colour", selection: $color)
                Stepper("Taps: \(taps)", value: $taps, in: 1...10)
            }
            .navigationTitle("New meaning")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let pattern = Array(repeating: 200, count: max(0, taps - 1))
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
